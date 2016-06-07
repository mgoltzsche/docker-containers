#!/bin/sh

FULL_MACHINE_NAME=$(hostname -f)
INSTANCE_ID=$(hostname -s)
INSTANCE_DIR="/etc/dirsrv/slapd-$INSTANCE_ID"
INSTANCE_LOG_DIR="/var/log/dirsrv/slapd-$INSTANCE_ID"

setupDirsrvInstance() {
	[ ! -d "$INSTANCE_DIR" ] || return 0 # Skip setup if already configured

	set -e
	: ${LDAP_INSTALL_INF_FILE:=/tmp/ds-config.inf}
	: ${LDAP_SERVER_PORT:=389}
	: ${LDAP_ADMIN_DOMAIN:=$(hostname -d)}
	: ${LDAP_ADMIN_DOMAIN_SUFFIX:=$(echo "dc=$LDAP_ADMIN_DOMAIN" | sed 's/\./,dc=/g')}
	: ${LDAP_ROOT_DN:='cn=dirmanager'}
	: ${LDAP_ROOT_DN_PWD:='Secret123'}
	: ${LDAP_CONFIG_DIRECTORY_ADMIN_ID:=admin}
	: ${LDAP_CONFIG_DIRECTORY_ADMIN_PWD:=$LDAP_ROOT_DN_PWD}
	: ${LDAP_SUFFIX:=$LDAP_ADMIN_DOMAIN_SUFFIX}
	: ${LDAP_INSTALL_LDIF_FILE:=suggest}
	: ${LDAP_OPTS:=-x -h localhost -p "$LDAP_SERVER_PORT" -D "$LDAP_ROOT_DN" -w "$LDAP_ROOT_DN_PWD"}

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

		echo "Installing LDAP server instance with:$(echo '';set | grep -E '^LDAP_' | sed -E 's/(^[^=]+_PWD=).+/\1***/')"
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

waitForService() {
	until timeout 1 bash -c "</dev/tcp/$1/$2" 2>/dev/null; do
		echo "Waiting for service $1:$2 to become available"
		sleep 1
	done
}

disableSlapdLogRotation() {
	# Disables slapd log rotation (to use named pipe)
	echo "Disabling log rotation"
	waitForService localhost $LDAP_SERVER_PORT
	echo "dn: cn=config
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
" | ldapmodify $LDAP_OPTS || exit 1
}

catPipe() {
	while true; do
		sed -u "s/]/] $2/g" "$1" || exit 1
	done
}

startLog() {
	set -e : ${LOGSTASH_HOST:=logstash}
	ACCESS_PIPE=$INSTANCE_LOG_DIR/access
	AUDIT_PIPE=$INSTANCE_LOG_DIR/audit
	ERROR_PIPE=$INSTANCE_LOG_DIR/errors
	PIPE_PATHS="$ACCESS_PIPE $AUDIT_PIPE $ERROR_PIPE"
	#PIPE_DEFS="ACCESS:$INSTANCE_LOG_DIR/access AUDIT:$INSTANCE_LOG_DIR/audit ERROR:$INSTANCE_LOG_DIR/errors"
	rm -rf /tmp/log-pipe $PIPE_PATHS || exit 1
	for PIPE in $PIPE_PATHS; do mkfifo $PIPE || exit 1; done
	if [ "$LOGSTASH_PORT" ]; then # Also log to logstash via tcp
		#/pipes.sh $PIPE_DEFS | telnet -E "$LOGSTASH_HOST" "$LOGSTASH_PORT" &

		mkfifo /tmp/log-pipe || exit 1
		catPipe $ACCESS_PIPE "ACCESS" >/tmp/log-pipe &
		LOG_PIDS="$LOG_PIDS $!"
		catPipe $AUDIT_PIPE "AUDIT" >/tmp/log-pipe &
		LOG_PIDS="$LOG_PIDS $!"
		catPipe $ERROR_PIPE "ERROR" >/tmp/log-pipe &
		LOG_PIDS="$LOG_PIDS $!"
		
		(
		while true; do
			waitForService $LOGSTASH_HOST $LOGSTASH_PORT
			# TODO: Retry sending last part when pipe breaks (due to log server connection loss) - or use nc -u (UDP) to not block the application at all and reduce connection overhead
			catPipe /tmp/log-pipe | telnet -E $LOGSTASH_HOST $LOGSTASH_PORT
		done
		echo "Exit log loop"
		) &
		LOG_PIDS="$LOG_PIDS $!"

		#(
		#	/pipes.sh $PIPE_DEFS | while read -r line; do
		#		echo "$line";
		#		until echo "$line" | telnet "$LOGSTASH_HOST" "$LOGSTASH_PORT"; do
		#			sleep 1 # Wait a second and retry to send log
		#		done
		#	done
		#) &
		#if ! ps "$!" >/dev/null; then
		#	echo "Failed to start logging" >&2
		#	exit 1
		#fi
	else
		#/pipes.sh $PIPE_DEFS &
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
			disableSlapdLogRotation
		fi

		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM # Register signal handler for orderly shutdown

		if [ ! "$CMD" = ns-slapd ]; then # LDAP operations
			# Wait for LDAP server to become available
			waitForService localhost $LDAP_SERVER_PORT
			"$CMD" $LDAP_OPTS $@
			terminateSynchronously $(slapdPID) $LOG_PIDS
		else
			wait
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
		if [ ! "$2" ]; then echo "Usage: $0 restore BACKUPFILE.tar.bz2" >&2; exit 1; fi
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
