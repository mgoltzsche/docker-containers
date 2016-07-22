#!/bin/sh

DOMAIN=$(hostname -d)
CERTIFICATE_NAME='server' # TODO: if this is dynamic the values in postfix/dovecot config have to be adjusted dynamically
SYSLOG_REMOTE_ENABLED=${SYSLOG_REMOTE_ENABLED:=false}
SYSLOG_HOST=${SYSLOG_HOST:=syslog}
SYSLOG_PORT=${SYSLOG_PORT:=514}
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

awaitSuccess() {
	MSG="$1"
	shift
	until $@; do
		echo "$MSG" >&2
		sleep 1
	done
}

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
	# Wait until syslog server is available to capture log
	RSYSLOG_FORWARDING_CFG=
	if [ "$SYSLOG_REMOTE_ENABLED" = 'true' ]; then
		awaitSuccess "Waiting for syslog UDP server $SYSLOG_HOST:$SYSLOG_PORT" nc -uzvw1 "$SYSLOG_HOST" "$SYSLOG_PORT" 2>/dev/null
		RSYSLOG_FORWARDING_CFG="*.* @$SYSLOG_HOST:$SYSLOG_PORT"
	fi

	cat > /etc/rsyslog.conf <<-EOF
		\$ModLoad immark.so # provides --MARK-- message capability
		\$ModLoad imuxsock.so # provides support for local system logging (e.g. via logger command)
		\$ModLoad omstdout.so # provides messages to stdout

		*.* :omstdout: # send everything to stdout
		$RSYSLOG_FORWARDING_CFG
	EOF
	[ $? -eq 0 ] || exit 1
	chmod 444 /etc/rsyslog.conf || exit 1
}

setupPostfix() {
	LDAP_DOMAIN_QUERY='(associatedDomain=%s)'
	LDAP_DOMAIN_ATTR='associatedDomain'
	LDAP_MAILBOX_QUERY='(&(objectClass=inetOrgPerson)(|(mail=%s)(mailAlternateAddress=%s)))'

	echo "Configuring postfix ..."
	mkdir -p /etc/postfix/ldap &&
	chmod 00755 /etc/postfix/ldap &&
	chmod 644 /etc/postfix/main.cf &&
	# Set hostname in main.cf
	sed -Ei 's/^myhostname\s*=.*$/myhostname = mail.algorythm.dex/' /etc/postfix/main.cf &&
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
	cat > "$1" <<-EOF
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
	cat > /etc/dovecot/dovecot-ldap.conf.ext <<-EOF
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

backup() {
	# TODO: backup without shutting down MTA by moving queued mails to hold queue using
	#   postsuper -h ALL
	# and requeue them somehow on restore
	stopDovecot &&
	stopPostfix || exit 1
	BACKUP_DATE=$(date +'%y-%m-%d_%H%M%S')
	BACKUP_DIR=/backup/mail-$BACKUP_DATE
	mkdir -p $BACKUP_DIR/etc &&
	cp /etc/{dovecot/dovecot.conf,postfix/{main.cf,master.cf}} $BACKUP_DIR/etc/ &&
	cp -R /var/mail $BACKUP_DIR/maildir &&
	cp -R /var/spool/postfix $BACKUP_DIR/postfix-queue
	startPostfix &&
	startDovecot
}

restore() {
	stopDovecot &&
	stopPostfix || exit 1
	BACKUP_DATE=$(date +'%y-%m-%d_%H%M%S')
	BACKUP_DIR=/backup/mail-$BACKUP_DATE
	rm -rf /var/mail &&
	cp -R $BACKUP_DIR/mail /var/mail &&
	cp -R $BACKUP_DIR/postfix-queue /var/spool/postfix &&
	chown -R vmail:vmail /var/mail &&
	startPostfix &&
	startDovecot
}

startSyslog() {
	# Start rsyslog to collect postfix & dovecot logs and print them to stdout and send them to logstash
	export SYSLOGD="-m ${SYSLOG_MARK_INTERVAL:-60}" # Set syslog -- Mark -- interval in minutes (useful for health check)
	rsyslogd -n -f /etc/rsyslog.conf &
	SYSLOG_PID=$!
	awaitSuccess 'Waiting for local rsyslog' [ -S /dev/log ]
}

startPostfix() {
	/usr/sbin/postfix -c /etc/postfix start
}

stopPostfix() {
	POSTFIX_PID=$(cat /var/spool/postfix/pid/master.pid 2>/dev/null)
	kill $POSTFIX_PID 2>/dev/null || echo "Couldn't terminate postfix since it is not running" >&2
	awaitTermination $POSTFIX_PID
}

startDovecot() {
	DOVECOT_CONF=/etc/dovecot/dovecot.conf
	DOVECOT_BASEDIR=$(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //') &&
	mkdir -p "$DOVECOT_BASEDIR" && chown dovecot:dovecot "$DOVECOT_BASEDIR" && chmod 0755 "$DOVECOT_BASEDIR" &&
	/usr/sbin/dovecot -c "$DOVECOT_CONF"
}

stopDovecot() {
	DOVECOT_PID=$(cat $(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')master.pid 2>/dev/null)
	kill $DOVECOT_PID 2>/dev/null || echo "Couldn't terminate dovecot since it is not running" >&2
	awaitTermination $DOVECOT_PID
}

processTerminated() {
	! ps -o pid | grep -q ${1:-0}
}

awaitTermination() {
	awaitSuccess "" processTerminated $1
}

terminateGracefully() {
	# Terminate
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Disable termination call on signal to avoid infinite recursion
	stopDovecot
	stopPostfix
	kill $SYSLOG_PID
	awaitTermination $SYSLOG_PID
	exit 0
}

# Register signal handler for orderly shutdown
trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM

case "$1" in
	run)
		setup
		startSyslog
		if [ ! "$LDAP_STARTUP_CHECK_ENABLED" = 'false' ]; then
			awaitSuccess "Waiting for LDAP server $LDAP_HOST:$LDAP_PORT" nc -zvw1 "$LDAP_HOST" "$LDAP_PORT"
		fi
		startPostfix
		startDovecot
		wait
	;;
	backup|restore)
		$@
	;;
	*)
		exec $1
	;;
esac
