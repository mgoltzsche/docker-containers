#!/bin/sh

# Shows usage and exits program with error
showUsageAndExit() {
	cat >&2 <<-EOF
		Usage: $SCRIPT COMMAND
		COMMANDS:
		  initca CN
		  updateca
		  status SERIALORSUBJECTORCN
		  genkey KEYFILE
		  certreq KEYFILE CERTFILE CN
		  sign CERTFILE [SIGNEDCERTFILE]
		  revoke SERIALORSUBJECTORCN
		  gensignedcert KEYFILE CERTFILE CN
		  gensignedcerts SSLDIR CN1 [CN2, ...]
		  verify CERTFILE
		  showcerts FILEORSERVICE
		  encrypt OUTFILE
		  decrypt OUTFILE
		Examples:
		  Key generation:
		    $SCRIPT genkey mail-entity.key &&
		    $SCRIPT gencert mail-entity.key mail-cert-req.csr mail.example.org
		    # Send mail-cert-req.csr to CA and let it sign there with:
		    $SCRIPT sign mail-cert-req.csr mail-cert.pem
		  CA creation (key+cert) + entity key+cert generation and signing + verification:
		    $SCRIPT initca example.org &&
		    $SCRIPT gensignedcert mail-entity.key mail-cert.pem mail.example.org &&
		    $SCRIPT verify mail-cert.pem
		  Example with predefined directory and CNs only:
		    $SCRIPT initca example.org &&
		    $SCRIPT gensignedcerts exampledir mail.example.org web.example.org
	EOF
	exit 1
}

caDir() {
	DIR="$(grep -E '^\s*dir\s*=' $CRT_CA_CONF | sed -E 's/.*?=\s*//')"
	echo "$DIR" | grep -Eq '^/|^~' && echo "$DIR" || echo "$(dirname "$CRT_CA_CONF")/$DIR"
}

SCRIPT="$0"
CRT_CA_CONF="${CRT_CA_CONF:-$(readlink -f $(dirname "$0")/caconfig.cnf)}"
CA_DIR="$(readlink -f $(caDir))"
export CRT_CA_ROOT_KEY_PW="$CRT_CA_ROOT_KEY_PW"
CRT_CA_KEY_FILE=${CRT_CA_KEY_FILE:-$CA_DIR/private/caroot.key}
CRT_CA_CERT_FILE=${CRT_CA_CERT_FILE:-$CA_DIR/certs/cacert.pem}
CRT_CA_VALIDITY_DAYS=${CRT_CA_VALIDITY_DAYS:-3650}
CRT_CA_KEY_BITS=${CRT_CA_KEY_BITS:-4096}
CRT_ORGANIZATION=${CRT_ORGANIZATION:-algorythm.de}
CRT_COUNTRY=${CRT_COUNTRY:-DE}
CRT_STATE=${CRT_STATE:-Berlin}
CRT_CITY=${CRT_CITY:-Berlin}
CRT_CN=
CRT_VALIDITY_DAYS=${CRT_VALIDITY_DAYS:-730}
CRT_KEY_BITS=${CRT_KEY_BITS:-4096}

if [ "$CRT_CA_ROOT_KEY_PW" ]; then
	PASSOUT_ARGS='-passout env:CRT_CA_ROOT_KEY_PW'
	PASSIN_ARGS='-passin env:CRT_CA_ROOT_KEY_PW'
else
	PASSOUT_ARGS='-nodes'
	PASSIN_ARGS=
fi

export OPENSSL_CONF="$CRT_CA_CONF"

# Generates a new CA key and certificate or renewes the certificate.
# When CA certificate expires it has to be removed and this method called.
# When the CA key must be replaced all node certificates become invalid 
# and have to be resigned.
initCA() {
	CRT_CN=${CRT_CN:-$(hostname -d)}
	[ ! -f "$CRT_CA_CERT_FILE" ] || (echo "CA already initialized" >&2; false) || exit 1
	[ ! "$1" ] || CRT_CN="$1"
	([ "$CRT_CN" ] || (echo "CRT_CN, node's domain name or parameter must be set to e.g. example.org" >&2; false)) &&
	([ -f serial ] || echo '0001' > "$CA_DIR/serial") &&
	touch "$CA_DIR/index.txt" || exit 1
	SUBJ="$(subj "$CRT_CN")"
	if [ -f "$CRT_CA_KEY_FILE" ]; then
		echo "Renewing CA root certificate with:"; showParams
		# Renew/generate new certificate with existing key
		OUT="$(openssl req -new -x509 -extensions v3_ca \
			-subj "$SUBJ" -days "$CRT_CA_VALIDITY_DAYS" $PASSOUT_ARGS \
			-key "$CRT_CA_KEY_FILE" -out "$CRT_CA_CERT_FILE" -sha512 2>&1)" ||
		(echo "$OUT" >&2; false) || exit 1
	else
		echo "Generating new certificate authority with:"; showParams
		# Generate new key and certificate (-x509 option means the certificate will be self signed / no cert. req.)
		touch "$CRT_CA_KEY_FILE" &&
		chmod 600 "$CRT_CA_KEY_FILE" &&
		OUT="$(openssl req -newkey "rsa:$CRT_CA_KEY_BITS" -x509 -extensions v3_ca \
			-subj "$SUBJ" -days "$CRT_CA_VALIDITY_DAYS" $PASSOUT_ARGS \
			-keyout "$CRT_CA_KEY_FILE" -out "$CRT_CA_CERT_FILE" -sha512 2>&1)" ||
		(echo "$OUT" >&2; rm -f "$CRT_CA_KEY_FILE"; false) || exit 1
	fi
	c_rehash "$CA_DIR/certs" >/dev/null
}

# Generates the subject
subj() {
	echo "/C=$CRT_COUNTRY/ST=$CRT_STATE/L=$CRT_CITY/O=$CRT_ORGANIZATION/CN=$1"
}

# Generates a new private key.
generatePrivateKey() {
	[ ! -f "$1" ] || (echo "$1 already exists" >&2; false) || return 1
	touch "$1" &&
	chmod 600 "$1" &&
	OUT="$(openssl genrsa -out "$1" "$CRT_KEY_BITS" 2>&1)" ||
	(echo "$OUT" >&2; rm -f "$1"; false)
}

# Generates a new certificate request for the given private key.
generateCertReq() {
	echo "Generating new certificate with:"; showParams
	openssl req -new -key "$1" -out "$2" -sha512 -days "$CRT_VALIDITY_DAYS" -subj "$(subj "$3")"
}

# Signs the given certificate request.
signCert() {
	[ -f "$CRT_CA_KEY_FILE" -a -f "$CRT_CA_CERT_FILE" ] || (echo "CA key/certificate missing: $CRT_CA_KEY_FILE, $CRT_CA_CERT_FILE. Run initca or put your CA key/certificate there" >&2; false) || return 1
	DEST="$2"
	[ "$2" ] || DEST="$1"
	[ ! -f "$2" ] || [ "$1" = "$2" ] || (echo "$2 already exists" >&2; false) || return 1
	echo "Signing certificate ..."
	TMP_OUT=$(mktemp)
	openssl ca -batch -cert "$CRT_CA_CERT_FILE" -keyfile "$CRT_CA_KEY_FILE" -in "$1" -notext -out $TMP_OUT \
		-extensions v3_req -days "$CRT_VALIDITY_DAYS" $PASSIN_ARGS
	STATUS=$?
	[ $STATUS -ne 0 ] || rm -f "$1"
	[ $STATUS -ne 0 ] || mv $TMP_OUT "$DEST" || exit 1
	[ $STATUS -ne 0 ] || cat "$CRT_CA_CERT_FILE" >> "$DEST"
	[ $STATUS -ne 0 ] || c_rehash "$CA_DIR/certs" >/dev/null
	rm -f $TMP_OUT
	return $STATUS
}

# Invalidates the certificate for the given subject within the CA DB
revokeCert() {
	SUBJ="$(subj "$1")"
	SERIAL="$(certSerial "$1")" ||
	SERIAL="$(getLastCertSerial 'V' "$1")" ||
	SERIAL="$(getLastCertSerial 'V' "$SUBJ")" ||
	(echo "No valid certificate registered for $1" >&2; false) || return 1
	openssl ca -revoke "$CA_DIR/certs/$SERIAL.pem"
}

certSerial() {
	cat "$CA_DIR/index.txt" | cut -d '	' -f 4 | grep -Ex "0*$1"
}

# Gets certificate serial by given subject or returns error code
getLastCertSerial() {
	CRT_SERIAL="$(grep -E "$1\s.*$2\$" "$CA_DIR/index.txt" | tail -1 | cut -d '	' -f 4)"
	echo "$CRT_SERIAL"
	[ "$CRT_SERIAL" ]
}

isCertificateRequest() {
	cat "$1" 2>/dev/null | head -1 | grep -qw 'BEGIN CERTIFICATE REQUEST'
}

generateSignedEntityCert() {
	KEY_FILE="$1"
	CSR_FILE="$2"
	CRT_FILE="$3"
	CN="$4"
	if [ ! -f "$KEY_FILE" ] && [ ! -f "$CSR_FILE" ]; then
		generatePrivateKey "$KEY_FILE" || return 1
	fi
	if [ ! -f "$CSR_FILE" ] && [ ! -f "$CRT_FILE" ]; then
		generateCertReq "$KEY_FILE" "$CSR_FILE" "$CN" || return 1
	fi
	if ([ ! -f "$CRT_FILE" ] || isCertificateRequest "$CRT_FILE") && [ -f "$CSR_FILE" ]; then
		signCert "$CSR_FILE" "$CRT_FILE" || return 1
	fi
}

generateSignedEntityCerts() {
	SSL_DIR="$1"
	[ "$1" ] || (echo "$1 is not a directory" >&2; false) || return 1
	mkdir -p "$SSL_DIR/private" "$SSL_DIR/certs" || return 1
	shift
	while [ $# -ne 0 ]; do
		generateSignedEntityCert \
			"$SSL_DIR/private/${1}-entity.key" \
			"$SSL_DIR/certs/${1}-cert.csr" \
			"$SSL_DIR/certs/${1}-cert.pem" \
			"$1" || return 1
		shift
	done
}

showParams() {
	set | grep -E "^CRT_" | sed -E 's/([^=]+_PW)=.*/\1=***/' | xargs -n1 echo ' '
}

mkdir -p "$CA_DIR/private" "$CA_DIR/certs" || exit 1
F1="$(readlink -f "$2")"
F2="$(readlink -f "$3")"
cd "$(dirname "$CRT_CA_CONF")" || exit 1

case "$1" in
	initca)
		# Attention: Existing certificates validate against new CA certificate only if CA root key stays unchanged
		[ $# -eq 1 -o $# -eq 2 ] || showUsageAndExit
		initCA "$2"
	;;
	updateca)
		[ $# -eq 1 ] || showUsageAndExit
		[ -f "$CRT_CA_CERT_FILE" ] || (echo "CA not initialized. Run $SCRIPT initca first" >&2; false) || exit 1
		openssl ca -updatedb &&
		c_rehash "$CA_DIR/certs" >/dev/null
	;;
	status)
		[ $# -eq 2 ] || showUsageAndExit
		SUBJ="$(subj "$2")"
		SERIAL="$(certSerial "$2")" ||
		SERIAL="$(getLastCertSerial 'V' "$2")" ||
		SERIAL="$(getLastCertSerial '.' "$2")" ||
		SERIAL="$(getLastCertSerial  'V' "$SUBJ")" ||
		SERIAL="$(getLastCertSerial  '.' "$SUBJ")" ||
		(echo "No certificate registered for $2" >&2; false) || return 1
		openssl ca -status "$SERIAL"
	;;
	genkey)
		[ $# -eq 2 ] || showUsageAndExit
		generatePrivateKey "$F1" || exit $?
	;;
	certreq)
		[ $# -eq 3 -o $# -eq 4 ] || showUsageAndExit
		[ $# -eq 3 ] || CRT_CN="$4"
		[ "$CRT_CN" ] || (echo 'CRT_CN or last arg must be set' >&2; false) || return 1
		generateCertReq "$F1" "$F2" "$CRT_CN" || exit $?
	;;
	sign)
		[ $# -eq 2 -o $# -eq 3 ] || showUsageAndExit
		# TODO: sign remote cert req via SSH
		signCert "$F1" "$F2" || exit $?
	;;
	revoke)
		[ $# -eq 2 ] || showUsageAndExit
		revokeCert "$2"
	;;
	gensignedcert)
		[ $# -eq 4 ] || showUsageAndExit
		[ $# -eq 3 ] || CRT_CN="$4"
		[ "$CRT_CN" ] || (echo 'CRT_CN or last arg must be set' >&2; false) || return 1
		[ "$F1" ] || (echo "Invalid directory: $2" >&2; false) || exit 1
		generateSignedEntityCert "$F1" "$F2" "$F2" "$CRT_CN"
	;;
	gensignedcerts)
		[ $# -gt 2 ] || showUsageAndExit
		SSL_DIR="$F1"
		shift
		shift
		generateSignedEntityCerts "$SSL_DIR" $@
	;;
	verify)
		[ $# -eq 2 ] || showUsageAndExit
		[ -f "$F1" ] || (echo "Invalid file: $2" >&2; false) || exit 1
		echo "Verifying certificate ..."
		openssl verify -CAfile "$CRT_CA_CERT_FILE" -verbose "$F1"
	;;
	showcert)
		[ $# -eq 2 ] || showUsageAndExit
		if echo "$2" | grep -q ':'; then
			openssl s_client -showcerts -CAfile "$CRT_CA_CERT_FILE" -connect "$2"
		else
			openssl x509 -in "$F1" -noout -text
		fi
	;;
	encrypt)
		openssl rsautl -encrypt -inkey "$F1" -certin | base64 - | xargs | tr -d ' '
	;;
	decrypt)
		base64 -d | openssl rsautl -decrypt -inkey "$F1"
	;;
	*)
		showUsageAndExit
	;;
esac
