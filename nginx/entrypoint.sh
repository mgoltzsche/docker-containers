#!/bin/sh

SYSLOG_FORWARDING_ENABLED=${SYSLOG_FORWARDING_ENABLED:=false}
SYSLOG_HOST=${SYSLOG_HOST:=syslog}
SYSLOG_PORT=${SYSLOG_PORT:=514}
LDAP_ENABLED=${LDAP_ENABLED:=false}
LDAP_HOST=${LDAP_HOST:=ldap}
LDAP_PORT=${LDAP_PORT:=389}
LDAP_DOMAIN=${LDAP_DOMAIN:=$(hostname -d)}
LDAP_SUFFIX=${LDAP_SUFFIX:='dc='$(echo "$LDAP_DOMAIN" | sed s/\\./,dc=/g)}
LDAP_BIND_DN="${LDAP_BIND_DN:=cn=nginx,ou=System Users,$LDAP_SUFFIX}"
LDAP_BIND_PW="${LDAP_BIND_PW:=nginxSecret123}"
LDAP_GROUP_ATTR=${LDAP_GROUP_ATTR:=uniquemember}
LDAP_GROUP_ATTR_IS_DN=${LDAP_GROUP_ATTR_IS_DN:=on}
SSL_CERT_SUBJ=${SSL_CERT_SUBJ:="/C=DE/ST=Berlin/L=Berlin/O=$LDAP_DOMAIN"}

[ ! "$LDAP_ENABLED" = 'true' ] || [ ! "$LDAP_SUFFIX" = 'dc=' ] || (echo 'LDAP_SUFFIX not defined' >&2; false) || exit 1

setupNginx() {
	c_rehash /etc/ssl/certs >/dev/null && # Map certificates
	mkdir -pm 755 /etc/nginx/ssl/private /etc/nginx/ssl/certs &&
	echo -n "Syslog forwarding support: "
	if [ "$SYSLOG_FORWARDING_ENABLED" = true ]; then
		echo "enabled"
		awaitSuccess "Waiting for syslog UDP server $SYSLOG_HOST:$SYSLOG_PORT" nc -uzvw1 "$SYSLOG_HOST" "$SYSLOG_PORT"
		cat > /etc/nginx/conf.d/10-logging.conf <<-EOF
			error_log syslog:server=$SYSLOG_HOST:$SYSLOG_PORT;
			access_log syslog:server=$SYSLOG_HOST:$SYSLOG_PORT,facility=local7,tag=nginx,severity=info access;
		EOF
	else
		echo "disabled"
		cat > /etc/nginx/conf.d/10-logging.conf <<-EOF
			error_log /dev/stderr info;
			access_log /dev/stdout;
		EOF
	fi
	echo -n "LDAP support:          "
	if [ "$LDAP_ENABLED" = true ]; then
		echo "enabled"
		awaitSuccess "Waiting for LDAP server $LDAP_HOST:$LDAP_PORT" nc -zvw1 "$LDAP_HOST" "$LDAP_PORT"
		cat > /etc/nginx/conf.d/20-ldap.conf <<-EOF
			ldap_server ldap_master {
			  url ldap://$LDAP_HOST:$LDAP_PORT/$LDAP_SUFFIX?cn?sub?(objectClass=person);
			  binddn "$LDAP_BIND_DN";
			  binddn_passwd "$LDAP_BIND_PW";
			  group_attribute $LDAP_GROUP_ATTR;
			  group_attribute_is_dn $LDAP_GROUP_ATTR_IS_DN;
			}
		EOF
	else
		echo "disabled"
		echo > /etc/nginx/conf.d/20-ldap.conf
	fi
	setupSslCertificate server &&
	setupVirtualHosts &&
	generateDefaultIndexHtml
}

setupVirtualHosts() {
	rm -rf /etc/nginx/vhosts-generated/* || return 1
	VHOSTS="$(set | grep -Eo '^VHOST_[^=]+_NAME=.+' | sed -E 's/^VHOST_([^=]+)_NAME=.+/\1/g')"
	if [ "$VHOSTS" ]; then
		echo 'Configuring virtual hosts:'
		for VHOST in $VHOSTS; do
			VHOST_ID="$(echo "$VHOST" | tr '[:upper:]' '[:lower:]')"
			SERVER_NAME="$(eval "echo \"\$VHOST_${VHOST}_NAME\"")"
			PROXY_PASS="$(eval "echo \"\$VHOST_${VHOST}_PROXY_PASS\"")" # e.g.: http://127.0.0.1:8080/
			([ "$PROXY_PASS" ] || (echo "VHOST_${VHOST}_PROXY_PASS is not defined" >&2; false)) &&
			echo "Proxy $SERVER_NAME -> $PROXY_PASS" &&
			setupSslCertificate "$SERVER_NAME"
			cat > /etc/nginx/vhosts-generated/$VHOST_ID.conf <<-EOF
				server {
				  listen 80;
				  listen 443 ssl;
				  server_name $SERVER_NAME;
				  #root /usr/share/nginx/html;

				  ssl_certificate     /etc/nginx/ssl/certs/$SERVER_NAME.pem;
				  ssl_certificate_key /etc/nginx/ssl/private/$SERVER_NAME.key;

				  include proxy_params;

				  location / {
					proxy_pass $PROXY_PASS;
				  }
				}
			EOF
			[ $? -eq 0 ] || return 1
		done
	fi
}

setupSslCertificate() {
	mkdir -pm 0755 /etc/nginx/ssl/private /etc/nginx/ssl/certs || return 1
	KEY_FILE="/etc/nginx/ssl/private/$1.key"
	CERT_FILE="/etc/nginx/ssl/certs/$1.pem"
	SUBJ="$SSL_CERT_SUBJ/CN=$1"

	if [ -f "$KEY_FILE" -a -f "$CERT_FILE" ]; then
		echo "Using existing SSL certificate: $CERT_FILE"
	elif [ -f "$KEY_FILE" ]; then
		echo "WARN: Generating self-signed SSL certificate for '$SUBJ' using existing key $KEY_FILE"
		touch "$CERT_FILE" &&
		chmod 644 "$CERT_FILE" &&
		ERR="$(openssl req -new -x509 -days 730 -sha512 -subj "$SUBJ" \
			-key "$KEY_FILE" -out "$CERT_FILE" 2>&1)" || (echo "$ERR" >&2; false)
	else
		echo "WARN: Generating self-signed SSL key+certificate for '$SUBJ' into $KEY_FILE"
		touch "$KEY_FILE" &&
		chmod 600 "$KEY_FILE" &&
		# -x509 means self-signed/no cert. req.
		ERR="$(openssl req -new -newkey rsa:4096 -x509 -days 730 -nodes \
			-subj "$SUBJ" -sha512 \
			-keyout "$KEY_FILE" -out "$CERT_FILE" 2>&1)" || (echo "$ERR" >&2; false)
	fi
}

listServerNames() {
	cat /etc/nginx/vhosts-generated/*.conf /etc/nginx/vhosts/*.conf 2>/dev/null \
		| grep server_name | sed -E 's/^\s*server_name\s+(.*);/\1/g' \
		| tr ' ' '\n' | sort | uniq | grep -vx default
}

generateDefaultIndexHtml() {
	HTML="<html><head><title>Unknown site</title></head><body><h1>Unknown site</h1>"
	SERVER_NAMES="$(listServerNames)"
	if [ "$SERVER_NAMES" ]; then
		HTML="$HTML<p>Did you mean one of the sites below?</p><ul>"
		for SERVER_NAME in "$SERVER_NAMES"; do
			HTML="$HTML<li><a href=\"http://$SERVER_NAME/\" title=\"http://$SERVER_NAME/\">$SERVER_NAME</a></li>"
		done
		HTML="$HTML</ul>"
	else
		HTML="$HTML<p>No site configured!</p>"
	fi
	echo "$HTML</body></html>" > /usr/share/nginx/html/index.html
}

# Provides the nginx PID
nginxPid() {
	cat /var/run/nginx.pid 2>/dev/null
	return 0
}

# Runs the provided command until it succeeds.
# Takes the error message to be displayed if it doesn't succeed as first argument.
awaitSuccess() {
	MSG="$1"
	shift
	until $@ >/dev/null 2>/dev/null; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 1
	done
}

# Terminates the provided PID and waits until it is terminated
terminatePid() {
	kill $1 2>/dev/null
	awaitSuccess '' isProcessTerminated $1
}

# Tests if the provided PID is terminated
isProcessTerminated() {
	! ps -o pid | grep -wq ${1:-0}
}

# Terminates the whole container orderly
terminateGracefully() {
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Unregister signal handler to avoid infinite recursion
	terminatePid ${nginxPid}
	exit 0
}

case "$1" in
	nginx)
		(NGINX_PID=$(nginxPid) && [ ! "$NGINX_PID" ] || isProcessTerminated $NGINX_PID || (echo 'nginx is already running' >&2; false)) &&
		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM &&
		rm -f /var/run/nginx.pid &&
		setupNginx &&
		nginx -tq || exit $?
		$@ &
		echo "nginx started"
		wait
	;;
	*)
		$@
		exit $?
	;;
esac
