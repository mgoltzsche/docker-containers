#!/bin/sh

FULL_MACHINE_NAME=$(hostname -f)
INSTANCE_ID=$(hostname -s)
INSTANCE_DIR="/etc/dirsrv/slapd-$INSTANCE_ID"
INSTANCE_LOG_DIR="/var/log/dirsrv/slapd-$INSTANCE_ID"

setupDirsrvInstance() {
	set -e
	: ${LDAP_INSTALL_INF_FILE:=/tmp/ds-config.inf}
	: ${LDAP_SERVER_PORT:=389}
	: ${LDAP_ADMIN_DOMAIN:=$(hostname -d)}
	: ${LDAP_ADMIN_DOMAIN_SUFFIX:=$(echo "dc=$LDAP_ADMIN_DOMAIN" | sed 's/\./,dc=/g')}
	: ${LDAP_ROOT_DN:='cn=directory manager'}
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
		echo "
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
		" > "$LDAP_INSTALL_INF_FILE" || exit 2
	fi

    # Disable SELinux (taken from https://github.com/ioggstream/dockerfiles/blob/master/389ds/tls/entrypoint.sh)
    rm -fr /usr/lib/systemd/system
    sed -i 's/updateSelinuxPolicy($inf);//g' /usr/lib64/dirsrv/perl/*
    sed -i '/if (@errs = startServer($inf))/,/}/d' /usr/lib64/dirsrv/perl/*

	# Install LDAP server with config file
	setup-ds.pl -sdf "$LDAP_INSTALL_INF_FILE" || exit 3
	rm -rf /tmp/ds-config.inf 2>/dev/null
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
	DIRSRV_PID=$(ps h -o pid -C ns-slapd)
	kill $DIRSRV_PID 2>/dev/null || echo "Couldn't terminate 389 directory server since it is not running" >&2
	awaitTermination $DIRSRV_PID
	#kill $SYSLOG_PID
	#awaitTermination $SYSLOG_PID
	exit 0
}

case "$1" in
	dirsrv)
		mkdir -p "INSTANCE_LOG_DIR/{}"

		if [ ! -d "$INSTANCE_DIR" ]; then
			setupDirsrvInstance # Install if directory doesn't exist
			sleep 3
		fi

		shift
		ns-slapd -D $INSTANCE_DIR $@ &&
		echo "LDAP server started"
		# TODO: handle proper logging: maybe try fedora image: if it contains newer version of 389ds it may be able to log to syslog as in http://directory.fedoraproject.org/docs/389ds/design/logging-multiple-backends.html
		tail -f $INSTANCE_LOG_DIR/{access,errors} --max-unchanged-stats=5 &
		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM # Register signal handler for orderly shutdown
		wait
	;;
	*)
		exec "$@"
	;;
esac

