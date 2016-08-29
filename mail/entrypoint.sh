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
DOVECOT_CONF=/etc/dovecot/dovecot.conf
RESTORE_BACKUP="$RESTORE_BACKUP"

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
		echo "Using existing SSL certificate /etc/ssl/{certs/server.pem,private/server.key}"
		c_rehash /etc/ssl/certs >/dev/null # Map certificates (ca-certificates.csr warning can be ignored safely)
		return $?
	fi
	mkdir -p -m 0755 /etc/ssl/private /etc/ssl/certs /etc/ssl/server/private /etc/ssl/server/certs || return 1
	KEY_FILE="/etc/ssl/server/private/$MACHINE_FQN.key"
	CERT_FILE="/etc/ssl/server/certs/$MACHINE_FQN.pem"
	SUBJ="$SSL_CERT_SUBJ/CN=$MACHINE_FQN"

	if [ -f "$KEY_FILE" -a -f "$CERT_FILE" ]; then
		echo "Using existing SSL certificate: $CERT_FILE"
	elif [ -f "$KEY_FILE" ]; then
		echo "WARNING: Generating self-signed SSL certificate for '$SUBJ' using existing key $KEY_FILE"
		touch "$CERT_FILE" &&
		chmod 644 "$CERT_FILE" &&
		ERR="$(openssl req -new -x509 -days 730 -sha512 -subj "$SUBJ" \
			-key "$KEY_FILE" -out "$CERT_FILE" 2>&1)" || (echo "$ERR" >&2; false)
	else
		echo "WARNING: Generating self-signed SSL key+certificate for '$SUBJ' into $KEY_FILE"
		touch "$KEY_FILE" &&
		chmod 600 "$KEY_FILE" &&
		# -x509 means self-signed/no cert. req.
		ERR="$(openssl req -new -newkey rsa:4096 -x509 -days 730 -nodes \
			-subj "$SUBJ" -sha512 \
			-keyout "$KEY_FILE" -out "$CERT_FILE" 2>&1)" || (echo "$ERR" >&2; false)
	fi

	rm -f /etc/ssl/certs/server.pem /etc/ssl/private/server.key &&
	c_rehash /etc/ssl/certs >/dev/null && # Map certificates (ca-certificates.csr warning can be ignored safely)
	ln -s "$KEY_FILE" /etc/ssl/private/server.key &&
	ln -s "$CERT_FILE" /etc/ssl/certs/server.pem || return 1
}

setupPostfix() {
	LDAP_DOMAIN_QUERY='(associatedDomain=%s)'
	LDAP_DOMAIN_ATTR='associatedDomain'
	LDAP_MAILBOX_QUERY='(&(objectClass=mailRecipient)(|(mail=%s)(mailAlternateAddress=%s)))'
	echo "Configuring postfix ..."
	chown root:root /var/spool/postfix /var/spool/postfix/pid &&
	mkdir -p /etc/postfix/ldap &&
	chmod 0755 /var/spool/postfix /var/spool/postfix/pid /etc/postfix/ldap &&
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
	[ $? -eq 0 ] &&
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
	mkdir -p -m 0700 /var/mail &&
	chown -R vmail:vmail /var/mail &&
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
		user_attrs = =mail=maildir:/var/mail/%d/%n/
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
	set | grep -E '^SSL_|^LOGSTASH_|^LDAP_|^TRUSTED_|^INSTALL_' | sed -E 's/(^[^=]+_(PASSWORD|PW)=).+/\1***/i' | xargs -n1 echo ' ' # Show variables

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

	# Setup postfix+dovecot+ldap configuration
	setupSslCertificate &&
	setupPostfix &&
	setupDovecot || exit 1
}

backup() {
	# ATTENTION: When migrating one mail server to another make sure 
	#   postfix is shutdown before starting the backup to avoid mail loss.
	#   Additionally use a backup MX server to avoid any MTA down time:
	#     Queues incoming mail and forwards it to primary mail server
	#     when available again
	RESTART=0
	! testContainerStarted || RESTART=1
	([ "$1" ] || (echo "Usage: backup DESTINATION" >&2; false)) &&
	([ ! -f "$1" ] || (echo "Backup file $1 already exists" >&2; false)) || return 1
	echo "Backing up mail server. Mail systems will be shutdown meanwhile and restarted afterwards."
	echo "HINT: When migrating postfix make sure it is shutdown before backup"
	echo "      and start container with backup command to migrate consistent state."
	echo "HINT: Run MX backup server to make sure to catch all incoming mail during downtime of primary server."
	date +'%y-%m-%d %H:%M:%S' > /mail-backup-date.txt &&
	stopDovecot &&
	stopPostfix || return 1
	postsuper -h ALL && # Move queued mails to hold queue where they are not touched by postgres
	tar -cjf "$1" -C / \
			mail-backup-date.txt \
			etc/postfix/main.cf \
			etc/postfix/master.cf \
			etc/dovecot/dovecot.conf \
			var/mail \
			var/spool/postfix/hold \
		|| (echo 'Backup failed' >&2; rm -f "$1" false)
	STATUS=$?
	postsuper -r ALL || return 1 # Requeue hold mails
	if [ "$STATUS" -eq 0 -a "$RESTART" -eq 1 ]; then
		startPostfix &&
		startDovecot || return 1
	fi
	rm -rf /mail-backup-date.txt
	return $STATUS
}

# Restores a backup. ATTENTION: Also requeues hold mails contained in the backup.
restore() {
	RESTART=0
	! testContainerStarted || RESTART=1
	([ "$1" ] || (echo "Usage: restore BACKUP" >&2; false)) &&
	([ -f "$1" ] || (echo "Backup file $1 does not exist" >&2; false)) &&
	BACKUP_FILES="$(tar tjf "$1")" &&
	((echo "$BACKUP_FILES" | grep -Eq '^var/mail/.+' && echo "$BACKUP_FILES" | grep -Eq '^var/spool/postfix/hold/' && echo "$BACKUP_FILES" | grep -Eq '^mail-backup-date.txt$') ||
		(echo "Invalid backup format" >&2; false)) &&
	stopDovecot &&
	stopPostfix &&
	tar -xjf "$1" -C / var/mail var/spool/postfix/hold mail-backup-date.txt &&
	chown -R vmail:vmail /var/mail &&
	chown -R postfix:postfix /var/spool/postfix/hold &&
	chmod 0700 /var/mail /var/spool/postfix/hold &&
	echo "Restored backup from $(cat $BACKUP_DIR/mail-backup-date.txt)" &&
	postsuper -r ALL # Requeue hold mails from backup
	STATUS=$?
	if [ "$STATUS" -eq 0 -a "$RESTART" -eq 1 ]; then
		startPostfix &&
		startDovecot || return 1
	fi
	rm -f /mail-backup-date.txt
	return $STATUS
}

testSyslogRunning() {
	! processTerminated "$SYSLOG_PID" || exit 1
	[ -S /dev/log ]
}

# Start rsyslog to collect postfix & dovecot logs and both
# print them to stdout and send them to remote syslog server.
startSyslog() {
	rm -f /var/run/syslogd.pid
	RSYSLOG_FORWARDING_CFG=
	if [ "$SYSLOG_FORWARDING_ENABLED" = 'true' ]; then
		# Wait until syslog server is available to capture log
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
	[ $? -eq 0 ] &&
	chmod 444 /etc/rsyslog.conf || exit 1
	rsyslogd -n -f /etc/rsyslog.conf &
	SYSLOG_PID=$!
	awaitSuccess 'Waiting for local rsyslog' testSyslogRunning
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
	kill $SYSLOG_PID 2>/dev/null
	awaitTermination $SYSLOG_PID
	exit 0
}

testContainerStarted() {
	ps -o comm | grep -Eq '^dovecot|^master'
}

# Register signal handler for orderly shutdown
trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM

case "$1" in
	run)
		! testContainerStarted || (echo "Can be run as container start command only" >&2; false) || exit 1
		setup
		rm -f /var/spool/postfix/pid/master.pid "$(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')master.pid"
		startSyslog
		if [ ! "$LDAP_STARTUP_CHECK_ENABLED" = 'false' ]; then
			awaitSuccess "Waiting for LDAP server $LDAP_HOST:$LDAP_PORT" nc -zvw1 "$LDAP_HOST" "$LDAP_PORT"
		fi
		# TODO: restore backup when env var present and container not initialized
		if [ "$RESTORE_BACKUP" ]; then
			if [ "$(ls /var/mail)" ]; then
				echo "Not restoring backup since /var/mail already contains contents"
			else
				restore "$RESTORE_BACKUP" || exit 1
			fi
		fi
		startPostfix &&
		startDovecot || (terminateGracefully; false) || exit 1
		wait
	;;
	backup|restore)
		$@
	;;
	*)
		exec $1
	;;
esac
