#!/bin/sh

FULL_MACHINE_NAME=$(hostname -f)
INSTANCE_ID=${INSTANCE_ID:=$(hostname -s)}
INSTANCE_DIR="/etc/dirsrv/slapd-$INSTANCE_ID"
INSTANCE_LOG_DIR="/var/log/dirsrv/slapd-$INSTANCE_ID"

# Attention set cannot be used since it changes program arguments which are required below
LDAP_SERVER_PORT=${LDAP_SERVER_PORT:=389}
LDAP_ROOT_DN=${LDAP_ROOT_DN:='cn=dirmanager'}
LDAP_ROOT_DN_PWD=${LDAP_ROOT_DN_PWD:='Secret123'}
LDAP_OPTS=${LDAP_OPTS:=-x -h localhost -p "$LDAP_SERVER_PORT" -D "$LDAP_ROOT_DN" -w "$LDAP_ROOT_DN_PWD"}
LDAP_ADMIN_DOMAIN=${LDAP_ADMIN_DOMAIN:=$(hostname -d)}
LDAP_ADMIN_DOMAIN_SUFFIX=${LDAP_ADMIN_DOMAIN_SUFFIX:=$(echo "dc=$LDAP_ADMIN_DOMAIN" | sed 's/\./,dc=/g')}
LDAP_SUFFIX=${LDAP_SUFFIX:=$LDAP_ADMIN_DOMAIN_SUFFIX}

setupDirsrvInstance() {
	if [ -d "$INSTANCE_DIR" ]; then
		# Reset directory manager password if instance already configured
		echo "Resetting directory manager password"
		ROOT_PWD_HASH=$(encodeLdapPassword "$LDAP_ROOT_DN_PWD") &&
		ROOT_PWD_HASH=$(echo "$ROOT_PWD_HASH" | xargs | sed -E 's/ +/\\n /') &&
		sed -i -E "s/^(nsslapd-rootpw:) .*/\1: $ROOT_PWD_HASH/g" "$INSTANCE_DIR/dse.ldif" || exit 1
		return 0 # Skip setup if already configured
	fi

	set -e
	: ${LDAP_INSTALL_INF_FILE:=/tmp/ds-config.inf}
	: ${LDAP_INSTALL_LDIF_FILE:=suggest}
	: ${LDAP_CONFIG_DIRECTORY_ADMIN_ID:=admin}
	: ${LDAP_CONFIG_DIRECTORY_ADMIN_PWD:=$LDAP_ROOT_DN_PWD}

	if [ -f "$LDAP_INSTALL_INF_FILE" ]; then
		echo "Installing LDAP server instance from configuration file $LDAP_INSTALL_INF_FILE"
	else
		if [ -z "$LDAP_ROOT_DN_PWD" ] || [ "$LDAP_ROOT_DN_PWD" = 'Secret123' ]; then
			LDAP_ROOT_DN_PWD='Secret123'
			echo "WARN: No LDAP_ROOT_DN_PWD env var set. Using default password: '$LDAP_ROOT_DN_PWD'." >&2
		fi
		if ! echo "$FULL_MACHINE_NAME" | grep -q '\.'; then
			echo "Set a fully qualified hostname using docker's -h option. E.g: -h host.domain" >&2
			exit 1
		fi

		echo "Installing LDAP server instance with:$(echo '';set | grep -E '^LDAP_' | sed -E 's/(^[^=]+_PWD=).+/\1***/' | grep -Ev '^LDAP_USER_' | xargs -n1 echo ' ')"
		echo > "$LDAP_INSTALL_INF_FILE" "
[General]
FullMachineName= $FULL_MACHINE_NAME
AdminDomain= $LDAP_ADMIN_DOMAIN
SuiteSpotUserID= nobody
SuiteSpotGroup= nobody
ConfigDirectoryAdminID= $LDAP_CONFIG_DIRECTORY_ADMIN_ID
ConfigDirectoryAdminPwd= $LDAP_CONFIG_DIRECTORY_ADMIN_PWD

[slapd]
ServerIdentifier= $INSTANCE_ID
ServerPort= $LDAP_SERVER_PORT
Suffix= $LDAP_SUFFIX
RootDN= $LDAP_ROOT_DN
RootDNPwd= $LDAP_ROOT_DN_PWD
InstallLdifFile= $LDAP_INSTALL_LDIF_FILE
		" || exit 1
	fi

    # Disable SELinux (taken from https://github.com/ioggstream/dockerfiles/blob/master/389ds/tls/entrypoint.sh)
    rm -fr /usr/lib/systemd/system
    sed -i 's/updateSelinuxPolicy($inf);//g' /usr/lib64/dirsrv/perl/*
    sed -i '/if (@errs = startServer($inf))/,/}/d' /usr/lib64/dirsrv/perl/*

	# Install LDAP server with config file
	setup-ds.pl -sdf "$LDAP_INSTALL_INF_FILE" || exit 1
	rm -rf /tmp/ds-config.inf 2>/dev/null
}

setupSystemUsers() {
	LDAP_USERS="$(set | grep -Eo '^LDAP_USER_DN_[^=]+' | sed 's/^LDAP_USER_DN_//')" # prevent user created from LDAP_USER_*_PASSWORD var

	if [ "$LDAP_USERS" ]; then
		waitForTcpService localhost $LDAP_SERVER_PORT

		for LDAP_USER_KEY in "$LDAP_USERS"; do
			LDAP_USER_DN=$(eval "echo \$LDAP_USER_DN_$LDAP_USER_KEY")
			LDAP_USER_PASSWORD=$(eval "echo \$LDAP_USER_PW_$LDAP_USER_KEY")
			LDAP_USER_PW_HASH=$(encodeLdapPassword "$LDAP_USER_PASSWORD")
			LDAP_USER_PREFIX=$(echo "$LDAP_USER_DN" | grep -Pio '^[a-z]+=[a-z0-9_\- ]+(?=,)' | sed 's/=/: /')
			LDAP_USER_EMAIL=$(eval "echo \$LDAP_USER_EMAIL_$LDAP_USER_KEY")
			LDAP_USER_EMAIL=${LDAP_USER_EMAIL:-$(echo "$LDAP_USER_PREFIX" | grep -Po '(?<=: ).*')"@service.$LDAP_ADMIN_DOMAIN"}

			if [ ! "$LDAP_USER_DN" ]; then
				echo "No LDAP user DN defined for $LDAP_USER_KEY" >&2
				echo "Set LDAP_USER_DN_$LDAP_USER_KEY='cn=user,ou=Special Users,dc=example,dc=org'" >&2
				exit 1
			fi

			if [ ! "$LDAP_USER_PASSWORD" ]; then
				echo "No password defined for LDAP user $LDAP_USER_KEY: $LDAP_USER_DN" >&2
				echo "Set LDAP_USER_PW_${LDAP_USER_KEY} env var" >&2
				exit 1
			fi

			if [ ! "$LDAP_USER_PREFIX" ]; then
				echo "Invalid DN format for LDAP_USER_KEY: $LDAP_USER_DN" >&2
				echo "Expecting e.g.: cn=example,ou=Special Users,dc=example,dc=org" >&2
				exit 1
			fi

			if ! ldapsearch $LDAP_OPTS -b "$LDAP_USER_DN" -LLL + * >/dev/null; then
				# Create user if not exists
				echo "Adding LDAP user $LDAP_USER_DN"
				LDIF="
dn: $LDAP_USER_DN
objectClass: applicationProcess
objectClass: simpleSecurityObject
objectClass: top
objectClass: mailRecipient
$LDAP_USER_PREFIX
mail: $LDAP_USER_EMAIL
mailForwardingAddress: max.goltzsche@algorythm.de
userPassword:: $LDAP_USER_PW_HASH
"
				if ! echo "$LDIF" | ldapadd $LDAP_OPTS; then
					echo "$LDIF" >&2
					exit 1
				fi
			else
				# Reset user password
				echo "Resetting LDAP user's password: $LDAP_USER_DN"

				LDIF="
dn: $LDAP_USER_DN
changetype: modify
replace: userPassword
userPassword:: $LDAP_USER_PW_HASH
"
				if ! echo "$LDIF" | ldapmodify $LDAP_OPTS; then
					echo "$LDIF" >&2
					exit 1
				fi
			fi
		done
	fi
}

encodeLdapPassword() {
	#pwdhash -s ssha512 "$1" | base64 -
	pwdhash -s ssha512 "$1" | base64 - | xargs | sed 's/ /\n /'
}

awaitSuccess() {
	MSG="$1"
	shift
	until $@ >/dev/null 2>/dev/null; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 1
	done
}

waitForTcpService() {
	until timeout 1 bash -c "</dev/tcp/$1/$2" 2>/dev/null; do
		echo "Waiting for TCP service $1:$2"
		sleep 1
	done
}

waitForUdpService() {
	until timeout 1 bash -c "</dev/udp/$1/$2" 2>/dev/null; do
		echo "Waiting for UDP service $1:$2"
		sleep 1
	done
}

disableSlapdLogRotation() {
	# Disables slapd log rotation (to use named pipe)
	echo "Disabling log rotation"
	waitForTcpService localhost $LDAP_SERVER_PORT
	ldapmodify $LDAP_OPTS <<-EOF
		dn: cn=config
		changetype: modify
		replace: nsslapd-accesslog-maxlogsperdir
		nsslapd-accesslog-maxlogsperdir: 1
		-
		replace: nsslapd-accesslog-logexpirationtime
		nsslapd-accesslog-logexpirationtime: -1
		-
		replace: nsslapd-accesslog-logrotationtime
		nsslapd-accesslog-logrotationtime: -1
		-
		replace: nsslapd-accesslog-logbuffering
		nsslapd-accesslog-logbuffering: off
		-
		replace: nsslapd-errorlog-maxlogsperdir
		nsslapd-errorlog-maxlogsperdir: 1
		-
		replace: nsslapd-errorlog-logexpirationtime
		nsslapd-errorlog-logexpirationtime: -1
		-
		replace: nsslapd-errorlog-logrotationtime
		nsslapd-errorlog-logrotationtime: -1
		-
		replace: nsslapd-auditlog-maxlogsperdir
		nsslapd-auditlog-maxlogsperdir: 1
		-
		replace: nsslapd-auditlog-logexpirationtime
		nsslapd-auditlog-logexpirationtime: -1
		-
		replace: nsslapd-auditlog-logrotationtime
		nsslapd-auditlog-logrotationtime: -1
	EOF
	[ $? -eq 0 ] || exit 1
}

catPipe() {
	if [ "$2" ]; then
		while true; do
			# Replace timestamp with log level
			sed -Eu "s/^\[[^]]+\] /$2 /g" "$1" || exit 1
		done
	else
		while true; do
			cat "$1" || exit 1
		done
	fi
}

startLog() {
	set -e : ${SYSLOG_HOST:=syslog} ${SYSLOG_PORT:=514}
	ACCESS_PIPE=$INSTANCE_LOG_DIR/access
	AUDIT_PIPE=$INSTANCE_LOG_DIR/audit
	ERROR_PIPE=$INSTANCE_LOG_DIR/errors
	PIPE_PATHS="$ACCESS_PIPE $AUDIT_PIPE $ERROR_PIPE"
	rm -rf /tmp/log-pipe $PIPE_PATHS || exit 1
	for PIPE in $PIPE_PATHS; do mkfifo $PIPE || exit 1; done
	SERVICE_HOST=$(hostname -s)
	if [ "$SYSLOG_REMOTE_ENABLED" ]; then # Also log to logstash via tcp
		waitForUdpService $SYSLOG_HOST $SYSLOG_PORT
		# TODO: Log directly with logger (maybe into local rsyslog) to avoid ending 0 bytes
		#       -> may not help because ending 0 bytes occur on pipe write
		mkfifo /tmp/log-pipe || exit 1
		catPipe $ACCESS_PIPE "ACCESS" >/tmp/log-pipe &
		LOG_PIDS="$LOG_PIDS $!"
		catPipe $AUDIT_PIPE "AUDIT" >/tmp/log-pipe &
		LOG_PIDS="$LOG_PIDS $!"
		catPipe $ERROR_PIPE "ERROR" >/tmp/log-pipe &
		LOG_PIDS="$LOG_PIDS $!"

		(
			while true; do
				logger -d -n $SYSLOG_HOST -P $SYSLOG_PORT -t "$SERVICE_HOST slapd" -s -f /tmp/log-pipe
				waitForUdpService $SYSLOG_HOST $SYSLOG_PORT
			done
		) &
		LOG_PIDS="$LOG_PIDS $!"
	else
		catPipe $ACCESS_PIPE "ACCESS" &
		LOG_PIDS="$LOG_PIDS $!"
		catPipe $AUDIT_PIPE "AUDIT" &
		LOG_PIDS="$LOG_PIDS $!"
		catPipe $ERROR_PIPE "ERROR" &
		LOG_PIDS="$LOG_PIDS $!"
	fi
	while ps $LOG_PIDS >/dev/null && [ ! -p "$INSTANCE_LOG_DIR/errors" ]; do sleep 1; done # Wait until pipes initialized
	ps $LOG_PIDS >/dev/null || exit 1
	chown root:nobody $PIPE_PATHS || exit 1
	chmod 660 $PIPE_PATHS || exit 1
}

slapdPID() {
	ps h -o pid -C ns-slapd
}

terminateSynchronously() {
	for PID in $@; do
		kill "$PID" 2>/dev/null
		awaitTermination "$PID"
	done
}

awaitTermination() {
	# Wait until process has been terminated
	while [ ! -z "$1" ] && ps "$1" >/dev/null; do
		sleep 1
	done
}

terminateGracefully() {
	echo "Terminating gracefully"
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Disable termination call on signal to avoid infinite recursion
	terminateSynchronously $(slapdPID) $LOG_PIDS
}

case "$1" in
	ns-slapd|ldapmodify|ldapadd|ldapdelete|ldapsearch)
		setupDirsrvInstance # Install if directory doesn't exist
		startLog
		CMD="$1"
		shift
		SLAPD_ARGS=
		if [ "$CMD" = ns-slapd ]; then
			SLAPD_ARGS=$@
			if [ "$(slapdPID)" ]; then
				echo "server is already running" >&2
				exit 1
			fi
		fi
		if [ ! "$(slapdPID)" ]; then
			ns-slapd -D "$INSTANCE_DIR" $SLAPD_ARGS || exit $?
			disableSlapdLogRotation || exit 1
			setupSystemUsers || exit 1
		fi

		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM # Register signal handler for orderly shutdown

		if [ "$CMD" = ns-slapd ]; then # LDAP operations
			wait
		else
			waitForTcpService localhost $LDAP_SERVER_PORT
			"$CMD" $LDAP_OPTS $@
			terminateSynchronously $(slapdPID) $LOG_PIDS
		fi
	;;
	dump)
		if [ ! "$2" ]; then echo "Usage: $0 dump BACKUPFILE.tar.bz2" >&2; exit 1; fi
		if [ -f "$2" ] || [ -d "$2" ]; then echo "Backup destination file $2 already exists" >&2; exit 1; fi
		ERROR=0
		ARCHIVE_FILE="$2"
		BACKUP_ID="${INSTANCE_ID}_$(date +'%y-%m-%d_%H-%M-%S')"
		BACKUP_TMP_DIR="/tmp/$BACKUP_ID"
		mkdir -p $(dirname $2) &&
		mkdir -p "$BACKUP_TMP_DIR" &&
		chmod -R 770 "$BACKUP_TMP_DIR" &&
		chown -R root:nobody "$BACKUP_TMP_DIR" || exit 1
		for DB_NAME in $(find /var/lib/dirsrv/slapd-$INSTANCE_ID/db/ -mindepth 1 -maxdepth 1 -type d | xargs -n 1 basename); do
			ns-slapd db2ldif -D /etc/dirsrv/slapd-$INSTANCE_ID -n $DB_NAME -a "$BACKUP_TMP_DIR/$INSTANCE_ID-$DB_NAME.ldif" >/dev/null || ERROR=$?
		done
		(cd /tmp && tar cjvf "$ARCHIVE_FILE" "$BACKUP_ID") || exit $?
		rm -rf "$BACKUP_TMP_DIR"
		exit $ERROR
	;;
	restore)
		if [ ! "$2" ]; then echo "Usage: $0 restore BACKUPFILE (tar.bz2)" >&2; exit 1; fi
		if [ ! -f "$2" ]; then echo "Backup file $2 does not exist" >&2; exit 1; fi
		if [ "$(slapdPID)" ]; then echo "You must terminate ns-slapd before you can restore dump" >&2; exit 1; fi
		setupDirsrvInstance # Install if directory doesn't exist
		EXTRACT_DIR=$(mktemp -d)
		(cd $EXTRACT_DIR && tar xjvf "$2") || exit $?
		chown -R root:nobody $EXTRACT_DIR && chmod -R 770 $EXTRACT_DIR
		BACKUP_TMP_DIR=$EXTRACT_DIR/$(ls $EXTRACT_DIR)
		ERROR=0
		for LDIF in $(ls $BACKUP_TMP_DIR | grep -E '\.ldif$'); do
			NAMES=$(echo $LDIF | sed -e 's/\.ldif$//')
			DB_NAME=$(echo $NAMES | cut -d - -f 2)
			ns-slapd ldif2db -D /etc/dirsrv/slapd-$INSTANCE_ID -n $DB_NAME -i $BACKUP_TMP_DIR/$LDIF || ERROR=$?
		done
		rm -rf $EXTRACT_DIR
		exit $ERROR
	;;
	*)
		exec "$@"
	;;
esac
