#!/bin/sh

DOMAIN=$(hostname -d)
CERTIFICATE_NAME='server' # TODO: if this is dynamic a template for dovecot.conf is required
LOGSTASH_ENABLED=${LOGSTASH_ENABLED:=false}
LOGSTASH_HOST=${LOGSTASH_HOST:=logstash}
LOGSTASH_PORT=${LOGSTASH_PORT:=5000}
LDAP_SUFFIX=${LDAP_SUFFIX:='dc='$(echo -n "$DOMAIN" | sed s/\\./,dc=/g)}
LDAP_HOST=${LDAP_HOST:=ldap}
LDAP_PORT=${LDAP_PORT:=389}
LDAP_USER_DN=${LDAP_USER_DN:="cn=vmail,ou=Special Users,$LDAP_SUFFIX"}
LDAP_USER_PW=${LDAP_USER_PW:="MailServerSecret123"}
LDAP_MAILBOX_SEARCH_BASE=${LDAP_MAILBOX_SEARCH_BASE:="$LDAP_SUFFIX"}
LDAP_DOMAIN_SEARCH_BASE=${LDAP_DOMAIN_SEARCH_BASE:="ou=Domains,$LDAP_SUFFIX"}

if [ -z "$DOMAIN" ]; then # Terminate when domain name cannot be determined
	echo 'hostname -d is undefined.' >&2
	echo 'Setup a proper hostname by adding an entry to /etc/hosts like this:' >&2
	echo ' 172.17.0.2      mail.example.org mail' >&2
	echo 'When using docker start the container with the -h option' >&2
	echo 'to configure the hostname. E.g.: -h mail.example.org' >&2
	exit 1
fi

echo 'Configuring mailing with:'
set | grep -E '^DOMAIN=|^LOGSTASH_|^CERTIFICATE_NAME=|^LDAP_' | sed -E 's/(^[^=]+_(PASSWORD|PW)=).+/\1***/i' | xargs -n1 echo ' ' # Show variables

setupSslCertificate() {
	# Generate SSL certificate if not available
	if [ -f "/etc/ssl/private/$CERTIFICATE_NAME.key" ]; then
		echo "Using provided server certificate /etc/ssl/private/$CERTIFICATE_NAME.key"
	else
		SUBJ="/C=DE/ST=Berlin/L=Berlin/O=algorythm/CN=$DOMAIN"
		echo "Generating new server certificate '$CERTIFICATE_NAME' for '$SUBJ' ..."
		openssl req -new -newkey rsa:4096 -days 2000 -nodes -x509 \
			-subj "$SUBJ" \
			-keyout "/etc/ssl/private/$CERTIFICATE_NAME.key" \
			-out "/etc/ssl/certs/$CERTIFICATE_NAME.crt" &&
		chmod 600 "/etc/ssl/private/$CERTIFICATE_NAME.key"
	fi
}

setupRsyslog() {
	# Wait until logstash is running to capture log
	RSYSLOG_LOGSTASH_CFG=
	if [ "$LOGSTASH_ENABLED" = 'true' ]; then
		until nc -vzw1 "$LOGSTASH_HOST" "$LOGSTASH_PORT" 2>/dev/null; do
			echo "Waiting for service $LOGSTASH_HOST:$LOGSTASH_PORT"
			sleep 1
		done
		RSYSLOG_LOGSTASH_CFG="*.* @$LOGSTASH_HOST:$LOGSTASH_PORT"
	fi

	# /etc/rsyslog: http://www.rsyslog.com/doc/
	cat > /etc/rsyslog.conf <<EOF
\$ModLoad immark.so # provides --MARK-- message capability
\$ModLoad imuxsock.so # provides support for local system logging (e.g. via logger command)
\$ModLoad omstdout.so # provides messages to stdout

*.* :omstdout: # send everything to stdout
$RSYSLOG_LOGSTASH_CFG
EOF
	[ $? -eq 0 ] || exit 1
	chmod 444 /etc/rsyslog.conf || exit 1
}

setupPostfix() {
	LDAP_DOMAIN_QUERY='(associatedDomain=%s)'
	LDAP_DOMAIN_ATTR='associatedDomain'
	LDAP_MAILBOX_QUERY='(&(objectClass=inetOrgPerson)(|(mail=%s)(mailAlternateAddress=%s)))'

	echo "Configuring postfix ..."
	MAIN_CF_TPL="$(cat /etc/postfix/main.cf.tpl)" &&
	mkdir -p /etc/postfix/ldap &&
	chmod 00755 /etc/postfix/ldap &&
	# Render main postfix configuration file with actual hostname
	echo "${MAIN_CF_TPL/\$\{MACHINE_FQN\}/$(hostname -f)}" > /etc/postfix/main.cf &&
	# Generate postfix LDAP configuration files
	cd /etc/postfix/ldap &&
	postfixLdapConf virtual_domains.cf   "$LDAP_DOMAIN_SEARCH_BASE"  "$LDAP_DOMAIN_QUERY"  "$LDAP_DOMAIN_ATTR" &&
	postfixLdapConf virtual_aliases.cf   "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" 'mailForwardingAddress' &&
	postfixLdapConf virtual_mailboxes.cf "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" "mail\nresult_format = %d/%u/" &&
	postfixLdapConf virtual_senders.cf   "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" 'mail' &&
	# Update postfix aliases DB
	newaliases
}

postfixLdapConf() {
	cat > "$1" <<EOF
# Postfix LDAP query
server_host = $LDAP_HOST
server_port = $LDAP_PORT
bind_dn = $LDAP_USER_DN
bind_pw = $LDAP_USER_PW
bind = yes
search_base = $2
query_filter = $3
result_attribute = $4
EOF
	test $? -eq 0 &&
	chmod 640 "$1" &&
	chown root:postfix "$1"
}

setupDovecot() {
	echo "Configuring dovecot ..."
	# Generate dovecot LDAP configuration
	cat > /etc/dovecot/dovecot-ldap.conf.ext <<EOF
# Dovecot LDAP mailbox resultion query (included in /etc/dovecot.conf)
hosts = $LDAP_HOST:$LDAP_PORT
dn = $LDAP_USER_DN
dnpass = $LDAP_USER_PW
tls = no
auth_bind = yes
base = $LDAP_MAILBOX_SEARCH_BASE
user_attrs = =mail=maildir:/var/vmail/%d/%n/
user_filter = (&(objectClass=inetOrgPerson)(mail=%u))
pass_attrs = 
pass_filter = (&(objectClass=inetOrgPerson)(mail=%u))
scope = subtree
ldap_version = 3
EOF
	test $? -eq 0 &&
	chmod 600 /etc/dovecot/dovecot-ldap.conf.ext &&
	# Link ldap conf as user db
	ln -sf /etc/dovecot/dovecot-ldap.conf.ext /etc/dovecot/dovecot-ldap-userdb.conf.ext
}

setup() {
	# Setup postfix+dovecot+ldap configuration
	chown root:root /var/spool/postfix /var/spool/postfix/pid &&
	setupRsyslog &&
	setupSslCertificate &&
	setupPostfix &&
	setupDovecot || exit 1
}

startSyslog() {
	# Start rsyslog to collect postfix & dovecot logs and print them to stdout and send them to logstash
	export SYSLOGD="-m ${SYSLOG_MARK_INTERVAL:-60}" # Set syslog -- Mark -- interval in minutes (useful for health check)
	rsyslogd -n -f /etc/rsyslog.conf &
	SYSLOG_PID=$!
}

startPostfix() {
	/usr/sbin/postfix -c /etc/postfix start
}

startDovecot() {
	DOVECOT_CONF=/etc/dovecot/dovecot.conf
	DOVECOT_BASEDIR=$(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //') &&
	mkdir -p "$DOVECOT_BASEDIR" && chown dovecot:dovecot "$DOVECOT_BASEDIR" && chmod 0755 "$DOVECOT_BASEDIR" &&
	/usr/sbin/dovecot -c "$DOVECOT_CONF"
}

awaitTermination() {
	if [ ! -z "$1" ]; then
		# Wait until process has been terminated
		while [ $(ps -ef | grep -Ec "^\s*$1 ") -ne 0 ]; do
			sleep 1
		done
	fi
}

terminateGracefully() {
	# Terminate
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Disable termination call on signal to avoid infinite recursion
	POSTFIX_PID=$(cat /var/spool/postfix/pid/master.pid 2>/dev/null)
	DOVECOT_PID=$(cat $(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')master.pid 2>/dev/null)
	kill $POSTFIX_PID 2>/dev/null || echo "Couldn't terminate postfix since it is not running" >&2
	kill $DOVECOT_PID 2>/dev/null || echo "Couldn't terminate dovecot since it is not running" >&2
	awaitTermination $POSTFIX_PID
	awaitTermination $DOVECOT_PID
	kill $SYSLOG_PID
	awaitTermination $SYSLOG_PID
	exit 0
}

# Register signal handler for orderly shutdown
trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM

if [ "$1" = 'run' ]; then
	setup
	startSyslog
	startPostfix
	startDovecot
	wait
elif [ "$1" = 'receivers' ]; then
	grep -E 'to=<.*?>' /var/log/maillog* | grep -v 'NOQUEUE: reject:' | grep -Po '(?<=to=\<)[^>]+' | sort | uniq
else
	exec $1
fi
