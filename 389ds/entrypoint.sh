#!/bin/sh

FULL_MACHINE_NAME=$(hostname -f)
INSTANCE_ID=$(hostname -s)
INSTANCE_DIR="/etc/dirsrv/slapd-$INSTANCE_ID"
INSTANCE_LOG_DIR="/var/log/dirsrv/slapd-$INSTANCE_ID"

setupDirsrvInstance() {
	if [ -d "$INSTANCE_DIR" ]; then # Skip setup if already configured
		return 0
	fi

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
		" || exit 2
	fi

    # Disable SELinux (taken from https://github.com/ioggstream/dockerfiles/blob/master/389ds/tls/entrypoint.sh)
    rm -fr /usr/lib/systemd/system
    sed -i 's/updateSelinuxPolicy($inf);//g' /usr/lib64/dirsrv/perl/*
    sed -i '/if (@errs = startServer($inf))/,/}/d' /usr/lib64/dirsrv/perl/*

	# Install LDAP server with config file
	setup-ds.pl -sdf "$LDAP_INSTALL_INF_FILE" || exit 3
	rm -rf /tmp/ds-config.inf 2>/dev/null
	awaitTermination $(slapdpid)
}

awaitTermination() {
	# Wait until process has been terminated
	while [ ! -z "$1" ] && ps "$1" >/dev/null; do
		sleep 1
	done
}

slapdpid() {
	ps h -o pid -C ns-slapd
}

terminateSynchronously() {
	kill "$1" 2>/dev/null || echo "Couldn't terminate 389 directory server since it is not running" >&2
	awaitTermination "$1"
}

terminateGracefully() {
	echo "Terminating gracefully"
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Disable termination call on signal to avoid infinite recursion
	terminateSynchronously $(slapdpid)
	#kill $SYSLOG_PID
	#terminateSynchronously $SYSLOG_PID
	exit 0
}

case "$1" in
	ns-slapd|ldapmodify|ldapadd|ldapdelete|ldapsearch)
		#mkdir -p "$INSTANCE_LOG_DIR"
		#mkfifo "$INSTANCE_LOG_DIR/"
		setupDirsrvInstance # Install if directory doesn't exist

		CMD="$1"
		shift
		SLAPD_ARGS=
		if [ "$CMD" = ns-slapd ]; then SLAPD_ARGS=$@; fi
		ns-slapd -D "$INSTANCE_DIR" $SLAPD_ARGS || exit $?

		# TODO: handle proper logging: maybe try fedora image: if it contains newer version of 389ds it may be able to log to syslog as in http://directory.fedoraproject.org/docs/389ds/design/logging-multiple-backends.html
		tail -f $INSTANCE_LOG_DIR/{access,errors} --max-unchanged-stats=5 &
		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM # Register signal handler for orderly shutdown

		if [ ! "$CMD" = ns-slapd ]; then # LDAP operations
			# Wait for LDAP server to become available
			until timeout 1 bash -c "</dev/tcp/localhost/$LDAP_SERVER_PORT" 2>/dev/null; do
				sleep 1
			done
			"$CMD" -x -h localhost -p "$LDAP_SERVER_PORT" -D "$LDAP_ROOT_DN" -w "$LDAP_ROOT_DN_PWD" $@
			terminateSynchronously $(slapdpid)
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
		if [ "$(slapdpid)" ]; then echo "You must terminate ns-slapd before you can restore dump" >&2; exit 1; fi
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
