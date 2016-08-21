#!/bin/sh

MACHINE_FQN=${MACHINE_FQN:-$(hostname -f)}
POSTMASTER_EMAIL=$POSTMASTER_EMAIL
SYSLOG_FORWARDING_ENABLED=${SYSLOG_FORWARDING_ENABLED:=false}
SYSLOG_HOST=${SYSLOG_HOST:=syslog}
SYSLOG_PORT=${SYSLOG_PORT:=514}
LDAP_DOMAIN=$(echo -n "$MACHINE_FQN" | sed -E 's/[^\.]+\.?//')
LDAP_SUFFIX=${LDAP_SUFFIX:='dc='$(echo -n "$LDAP_DOMAIN" | sed s/\\./,dc=/g)}
LDAP_HOST=${LDAP_HOST:=ldap}
LDAP_PORT=${LDAP_PORT:=389}
LDAP_USER_DN=${LDAP_USER_DN:="cn=vmail,ou=Special Users,$LDAP_SUFFIX"}
LDAP_USER_PW=${LDAP_USER_PW:="MailServerSecret123"}
LDAP_MAILBOX_SEARCH_BASE=${LDAP_MAILBOX_SEARCH_BASE:="$LDAP_SUFFIX"}
LDAP_DOMAIN_SEARCH_BASE=${LDAP_DOMAIN_SEARCH_BASE:="ou=Domains,$LDAP_SUFFIX"}
SSL_CERT_SUBJ=${SSL_CERT_SUBJ:="/C=DE/ST=Berlin/L=Berlin/O=$LDAP_DOMAIN"}
TRUSTED_NETWORKS=${TRUSTED_NETWORKS:=false} # true, false or actual value. ATTENTION: In trusted nets plaintext imap auth is allowed + smtp is less restrictive

awaitSuccess() {
	MSG="$1"
	shift
	until $@; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 1
	done
}

setupSslCertificate() {
	echo "Configuring SSL certificate ..."
	if [ -f "/etc/ssl/certs/server.pem" -a -f "/etc/ssl/private/server.key" ]; then
		echo "Using provided SSL certificate /etc/ssl/{certs/server.pem,private/server.key}"
		return 0
	fi
	mkdir -p -m 0755 /var/mail/ssl/private /var/mail/ssl/certs || return 1
	KEY_FILE="/var/mail/ssl/private/$MACHINE_FQN-key.key"
	CERT_FILE="/var/mail/ssl/certs/$MACHINE_FQN-cert.pem"
	SUBJ="$SSL_CERT_SUBJ/CN=$MACHINE_FQN"

	if [ -f "$KEY_FILE" -a -f "$CERT_FILE" ]; then
		echo "Using existing SSL certificate: $CERT_FILE"
	elif [ -f "$KEY_FILE" ]; then
		echo "Generating new SSL certificate for '$SUBJ' ..."
		openssl req -new -days 730 -sha512 -subj "$SUBJ" \
			-key "$KEY_FILE" -out "$CERT_FILE"
	else
		echo "Generating new SSL key+certificate for '$SUBJ' ..."
		# -x509 means selfsigned/no cert. req.
		openssl req -new -newkey rsa:4096 -days 730 -nodes -x509 \
			-subj "$SUBJ" -sha512 \
			-keyout "$KEY_FILE" -out "$CERT_FILE" &&
		chmod 600 "$KEY_FILE" || exit 1
	fi

	rm -f /etc/ssl/certs/server.pem /etc/ssl/private/server.key &&
	c_rehash /etc/ssl/certs >/dev/null && # Map certificates
	ln -s "$KEY_FILE" /etc/ssl/private/server.key &&
	ln -s "$CERT_FILE" /etc/ssl/certs/server.pem || exit 1
}

setupRsyslog() {
	# Wait until syslog server is available to capture log
	RSYSLOG_FORWARDING_CFG=
	if [ "$SYSLOG_FORWARDING_ENABLED" = 'true' ]; then
		awaitSuccess "Waiting for syslog UDP server $SYSLOG_HOST:$SYSLOG_PORT" nc -uzvw1 "$SYSLOG_HOST" "$SYSLOG_PORT" 2>/dev/null
		RSYSLOG_FORWARDING_CFG="*.* @$SYSLOG_HOST:$SYSLOG_PORT"
	fi

	cat > /etc/rsyslog.conf <<-EOF
		\$ModLoad imuxsock.so # provides local unix socket under /dev/log
		\$ModLoad omstdout.so # provides messages to stdout
		\$template stdoutfmt,"%syslogtag% %msg%\n" # light stdout format

		*.* :omstdout:;stdoutfmt # send everything to stdout
		$RSYSLOG_FORWARDING_CFG
	EOF
	[ $? -eq 0 ] || exit 1
	chmod 444 /etc/rsyslog.conf || exit 1
}

setupPostfix() {
	LDAP_DOMAIN_QUERY='(associatedDomain=%s)'
	LDAP_DOMAIN_ATTR='associatedDomain'
	LDAP_MAILBOX_QUERY='(&(objectClass=mailRecipient)(|(mail=%s)(mailAlternateAddress=%s)))'
	echo "Configuring postfix ..."
	mkdir -p /etc/postfix/ldap &&
	chmod 00755 /etc/postfix/ldap &&
	chmod 644 /etc/postfix/main.cf &&
	# Set MACHINE_FQN and TRUSTED_NETS in main.cf
	sed -Ei "s/^myhostname\s*=.*\$/myhostname = $MACHINE_FQN/" /etc/postfix/main.cf &&
	sed -Ei "s/^mynetworks\s*=.*\$/mynetworks = $TRUSTED_NETS/" /etc/postfix/main.cf &&
	# Generate postfix LDAP configuration files
	cd /etc/postfix/ldap &&
	postfixLdapConf virtual_domains.cf   "$LDAP_DOMAIN_SEARCH_BASE"  "$LDAP_DOMAIN_QUERY"  "$LDAP_DOMAIN_ATTR" &&
	postfixLdapConf virtual_aliases.cf   "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" 'mailForwardingAddress' &&
	postfixLdapConf virtual_mailboxes.cf "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" "$(printf 'mail\nresult_format') = %d/%u/" &&
	postfixLdapConf virtual_senders.cf   "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" 'mail' &&
	# Update postfix aliases DB
	cat > /etc/aliases <<-EOF
		postmaster: root
		root: $POSTMASTER_EMAIL
	EOF
	postalias /etc/aliases
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
	mkdir -p -m 0700 /var/mail/maildir &&
	chown -R vmail:vmail /var/mail/maildir &&
	sed -Ei "s/^login_trusted_networks\s*=.*\$/login_trusted_networks = $TRUSTED_NETS/" /etc/dovecot/dovecot.conf &&
	# Generate dovecot LDAP configuration
	cat > /etc/dovecot/dovecot-ldap.conf.ext <<-EOF
		# Dovecot LDAP mailbox resultion query (included in /etc/dovecot.conf)
		hosts = $LDAP_HOST:$LDAP_PORT
		dn = $LDAP_USER_DN
		dnpass = $LDAP_USER_PW
		tls = no
		auth_bind = yes
		base = $LDAP_MAILBOX_SEARCH_BASE
		user_attrs = =mail=maildir:/var/mail/maildir/%d/%n/
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
	if [ -z "$MACHINE_FQN" -o -z "$LDAP_DOMAIN" ]; then # Terminate when FQN or domain name cannot be determined
		cat >&2 <<-EOF
			MACHINE_FQN or LDAP_DOMAIN is undefined.
			These variables will be derived when you setup a proper MACHINE_FQN.
			E.g. add line to /etc/hosts: 172.17.0.2  mail.example.org mail
			When using docker start the container with the -h option
			to configure the machine FQN. E.g.: -h mail.example.org
		EOF
		exit 1
	fi

	[ "$POSTMASTER_EMAIL" ] || (echo 'POSTMASTER_EMAIL unset'; false) || exit 1

	echo 'Configuring mailing with:'
	set | grep -E '^SSL_|^LOGSTASH_|^LDAP_|^TRUSTED_' | sed -E 's/(^[^=]+_(PASSWORD|PW)=).+/\1***/i' | xargs -n1 echo ' ' # Show variables

	# Set/derive trusted networks
	TRUSTED_NETS='127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128'
	if [ "$TRUSTED_NETWORKS" = 'true' ]; then
		# Trust all networks this machine is in
		for IP in $(ip -o -4 addr list | grep -Eo '([0-9]+\.){3}[0-9]+/[0-9]+'); do
			IP_NET=$(ipcalc -s -n "$IP" | sed -E 's/[^=]+=//')
			IP_PFX=$(ipcalc -s -p "$IP" | sed -E 's/[^=]+=//')
			TRUSTED_NETS="$TRUSTED_NETS $IP_NET/$IP_PFX"
		done
	elif [ ! "$TRUSTED_NETWORKS" = 'false' ]; then
		TRUSTED_NETS="$TRUSTED_NETWORKS"
	fi
	TRUSTED_NETS="$(echo "$TRUSTED_NETS" | sed 's/\//\\\//g')" # Escape for sed

	# Setup postfix+dovecot+ldap+syslog configuration
	mkdir -p /var/mail/queue &&
	chown root:root /var/mail/queue &&
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
	cp -R /var/mail $BACKUP_DIR/mail &&
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
	chown -R vmail:vmail /var/mail/maildir &&
	chmod 0700 /var/mail/maildir
	startPostfix &&
	startDovecot
}

# Start rsyslog to collect postfix & dovecot logs and both
# print them to stdout and send them to remote syslog server.
startSyslog() {
	rm -f /var/run/syslogd.pid
	rsyslogd -n -f /etc/rsyslog.conf &
	SYSLOG_PID=$!
	awaitSuccess 'Waiting for local rsyslog' [ -S /dev/log ]
}

startPostfix() {
	/usr/sbin/postfix -c /etc/postfix start
}

stopPostfix() {
	POSTFIX_PID=$(cat /var/mail/queue/pid/master.pid 2>/dev/null)
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

testContainerStarted() {
	! ps -o comm | grep -Eq '^dovecot|^master' || (echo "Can be run as container start command only" >&2; false) || exit 1
}

# Register signal handler for orderly shutdown
trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM

case "$1" in
	run)
		testContainerStarted
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
