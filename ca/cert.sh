#!/bin/sh

# Shows usage and exits program with error
showUsageAndExit() {
	cat >&2 <<-EOF
		Usage: $SCRIPT initca [CN]|genkeycert KEYFILE CERTFILE [CN]|genkey KEYFILE|gencert KEYFILE CERTFILE [CN]
		  |sign CERTFILE [SIGNEDCERTFILE]|verify CERTFILE|showcerts URL
		Example key generation:
		  $SCRIPT genkey private/mail.key &&
		  $SCRIPT gencert private/mail.key certs/mail.pem mail.example.org
		Example CA creation (key+cert) + cert signing + verification:
		  $SCRIPT initca example.org &&
		  $SCRIPT genkeycert private/mail.key certs/mail.pem mail.example.org &&
		  $SCRIPT sign certs/mail.pem certs/mail-signed.pem &&
		  $SCRIPT verify certs/mail-signed.pem
	EOF
	exit 1
}

caDir() {
	DIR="$(grep -E '^\s*dir\s*=' $CA_CONF | sed -E 's/.*?=\s*//')"
	echo "$DIR" | grep -Eq '^/|^~' && echo "$DIR" || echo "$(dirname "$CA_CONF")/$DIR"
}

SCRIPT="$0"
CA_CONF="${CA_CONF:-$(readlink -f $(dirname "$0")/caconfig.cnf)}"
CA_DIR="${CA_DIR:-$(readlink -f $(caDir))}"
CA_COUNTRY=${CA_COUNTRY:-DE}
CA_STATE=${CA_STATE:-Berlin}
CA_CITY=${CA_CITY:-Berlin}
CA_ORGANIZATION=${CA_ORGANIZATION:-algorythm.de}
CA_CN=${CA_CN:-$(hostname -d)}
CA_ROOT_ARGS=${CA_ROOT_ARGS:--nodes} # Set empty to password protect CA key
CA_KEY_FILE=${CA_KEY_FILE:-$CA_DIR/private/ca-key.key}
CA_CERT_FILE=${CA_CERT_FILE:-$CA_DIR/certs/ca-cert.pem}
CA_VALIDITY_DAYS=${CA_VALIDITY_DAYS:-3650}
CA_KEY_BITS=${CA_KEY_BITS:-4096}
CRT_COUNTRY=${CRT_COUNTRY:-$CA_COUNTRY}
CRT_STATE=${CRT_STATE:-$CA_STATE}
CRT_CITY=${CRT_CITY:-$CA_CITY}
CRT_ORGANIZATION=${CRT_ORGANIZATION:-$CA_ORGANIZATION}
CRT_CN=${CRT_CN:-$(hostname -f)}
CRT_VALIDITY_DAYS=${CRT_VALIDITY_DAYS:-730}
CRT_KEY_BITS=${CRT_KEY_BITS:-4096}

# Generates a new CA key and certificate or renewes the certificate.
# When CA certificate expires it has to be removed and this method called.
# When the CA key must be replaced all node certificates become invalid 
# and have to be resigned.
initCA() {
	[ ! -f "$CA_CERT_FILE" ] || (echo "CA already initialized" >&2; false) || exit 1
	[ ! "$1" ] || CA_CN="$1"
	([ "$CA_CN" ] || (echo "CA_CN, node's domain name or parameter must be set to e.g. example.org" >&2; false)) &&
	([ -f serial ] || echo '0001' > "$CA_DIR/serial") &&
	touch "$CA_DIR/index.txt" || exit 1
	SUBJ="/C=$CA_COUNTRY/ST=$CA_STATE/L=$CA_CITY/O=$CA_ORGANIZATION/CN=$CA_CN"
	if [ -f "$CA_KEY_FILE" ]; then
		echo "Renew CA root certificate with:"; showParams CA
		# Renew/generate new certificate with existing key
		openssl req -new -x509 -extensions v3_ca $CA_ROOT_ARGS \
			-subj "$SUBJ" -days "$CA_VALIDITY_DAYS" -config "$CA_CONF" \
			-key "$CA_KEY_FILE" -out "$CA_CERT_FILE" -sha512
	else
		echo "Generate new certificate authority with:"; showParams CA
		# Generate new key and certificate (-x509 option means the certificate will be self signed / no cert. req.)
		touch "$CA_KEY_FILE" &&
		chmod 600 "$CA_KEY_FILE" &&
		openssl req -newkey "rsa:$CA_KEY_BITS" -x509 -extensions v3_ca $CA_ROOT_ARGS \
			-subj "$SUBJ" -days "$CA_VALIDITY_DAYS" -config "$CA_CONF" \
			-keyout "$CA_KEY_FILE" -out "$CA_CERT_FILE" -sha512 ||
		(rm -f "$CA_KEY_FILE"; false)
	fi
}

# Generates a new private key.
generatePrivateKey() {
	[ ! -f "$1" ] || (echo "$1 already exists" >&2; false) || exit 1
	touch "$1" &&
	chmod 600 "$1" &&
	openssl genrsa -out "$1" "$CRT_KEY_BITS" -conf "$CA_CONF" ||
	(rm -f "$1"; false)
}

# Generates a new unsigned certificate for the given private key (request).
generateCertificate() {
	[ "$CRT_CN" ] || (echo 'CRT_CN or node FQN must be set with e.g. mail.example.org' >&2; false) || exit 1
	echo "Generating new certificate with:"; showParams CRT
	openssl req -new -key "$1" -out "$2" -sha512 -days "$CRT_VALIDITY_DAYS" \
		-subj "/C=$CRT_COUNTRY/ST=$CRT_STATE/L=$CRT_CITY/O=$CRT_ORGANIZATION/CN=$CRT_CN" \
		-config "$CA_CONF"
}

# Signs the given certificate.
signCertificate() {
	[ ! -f "$F2" ] || (echo "$F2 already exists" >&2; false) || exit 1
	[ -f "$CA_KEY_FILE" -a -f "$CA_CERT_FILE" ] || (echo "CA key/certificate missing: $CA_KEY_FILE, $CA_CERT_FILE. Run initca or put your CA key/certificate there" >&2; false) || exit 1
	DEST="$2"
	[ "$2" ] || DEST="$1"
	[ ! -f "$2" ] || (echo "$2 already exists" >&2; false) || exit 1
	TMP_OUT=$(mktemp)
	openssl ca -batch -cert "$CA_CERT_FILE" -keyfile "$CA_KEY_FILE" -in "$1" -notext -out $TMP_OUT \
		-extensions v3_req -days "$CRT_VALIDITY_DAYS" -config "$CA_CONF"
	STATUS=$?
	[ $STATUS -ne 0 ] || rm -f "$1"
	[ $STATUS -ne 0 ] || mv $TMP_OUT "$DEST" || exit 1
	[ $STATUS -ne 0 ] || cat "$CA_CERT_FILE" >> "$DEST"
	rm -f $TMP_OUT
	return $STATUS
}

# Shows environment variables
showParams() {
	set | grep -E "^${1}_" | xargs -n1 echo ' '
}

mkdir -p "$CA_DIR/private" "$CA_DIR/certs" || exit 1
F1="$(readlink -f "$2")"
F2="$(readlink -f "$3")"
cd "$(dirname "$CA_CONF")" || exit 1

case "$1" in
	initca)
		# Attention: Existing certificates validate against new CA certificate only if CA root key stays unchanged
		[ $# -eq 1 -o $# -eq 2 ] || showUsageAndExit
		initCA "$2"
	;;
	genkey)
		[ $# -eq 2 ] || showUsageAndExit
		generatePrivateKey "$F1" || exit $?
	;;
	gencert)
		[ $# -eq 3 -o $# -eq 4 ] || showUsageAndExit
		[ $# -eq 3 ] || CRT_CN="$4"
		generateCertificate "$F1" "$F2" || exit $?
	;;
	genkeycert)
		[ $# -eq 3 -o $# -eq 4 ] || showUsageAndExit
		[ "$F1" ] || (echo "Invalid directory: $2" >&2; false) || exit 1
		[ ! -f "$F1" ] || (echo "$F1 already exists" >&2; false) || exit 1
		[ ! -f "$F2" ] || (echo "$F2 already exists" >&2; false) || exit 1
		[ $# -eq 3 ] || CRT_CN="$4"
		generatePrivateKey "$F1" &&
		generateCertificate "$F1" "$F2" || exit $?
	;;
	sign)
		[ $# -eq 2 -o $# -eq 3 ] || showUsageAndExit
		signCertificate "$F1" "$F2" || exit $?
	;;
	verify)
		[ $# -eq 2 ] || showUsageAndExit
		[ -f "$F1" ] || (echo "Invalid file: $2" >&2; false) || exit 1
		openssl verify -CAfile "$CA_CERT_FILE" -verbose "$F1"
	;;
	showcerts)
		[ $# -eq 2 ] || showUsageAndExit
		openssl s_client -showcerts -CAfile "$CA_CERT_FILE" -connect "$2"
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
