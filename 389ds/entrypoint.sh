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

	FIRST_START='true'

	set -e
	: ${LDAP_INSTALL_BACKUP_FILE:=}
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
		cat > "$LDAP_INSTALL_INF_FILE" <<-EOF
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
		EOF
		[ $? -eq 0 ] || exit 1
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

			if ldapsearch $LDAP_OPTS -b "$LDAP_USER_DN" -LLL + * >/dev/null; then
				# Reset user password
				echo "Resetting LDAP user's password: $LDAP_USER_DN"
				LDAP_CHANGE_CMD=ldapmodify
				LDIF="$(cat <<-EOF
					dn: $LDAP_USER_DN
					changetype: modify
					replace: userPassword
					userPassword:: $LDAP_USER_PW_HASH
				EOF
				)"
				[ $? -eq 0 ] || exit 1
			else
				# Create user if not exists
				echo "Adding LDAP user $LDAP_USER_DN"
				LDAP_CHANGE_CMD=ldapadd
				LDIF="$(cat <<-EOF
					dn: $LDAP_USER_DN
					objectClass: applicationProcess
					objectClass: simpleSecurityObject
					objectClass: top
					objectClass: mailRecipient
					$LDAP_USER_PREFIX
					mail: $LDAP_USER_EMAIL
					mailForwardingAddress: max.goltzsche@algorythm.de
					userPassword:: $LDAP_USER_PW_HASH
				EOF
				)"
				[ $? -eq 0 ] || exit 1
			fi
			$LDAP_CHANGE_CMD $LDAP_OPTS >/dev/null <<< "$LDIF" || (echo "$LDIF">&2;false) || exit 1
		done
	fi
}

encodeLdapPassword() {
	pwdhash -s ssha512 "$1" | base64 - | xargs | sed 's/ /\n /' || exit 1
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
	awaitSuccess "Waiting for TCP service $1:$2" timeout 1 bash -c "</dev/tcp/$1/$2"
}

setupSlapdLogging() {
	waitForTcpService localhost $LDAP_SERVER_PORT
	echo "Configuring slapd syslog logging"
	ldapmodify $LDAP_OPTS >/dev/null <<-EOF
		dn: cn=config
		changetype: modify
		replace: nsslapd-logging-backend
		nsslapd-logging-backend: syslog
		-
		replace: nsslapd-accesslog-logbuffering
		nsslapd-accesslog-logbuffering: off
	EOF
	[ $? -eq 0 ] || exit 1
}

startRsyslog() {
	ps h -o pid -C rsyslogd >/dev/null && return 1
	# Configure syslog forwarding and wait for remote syslog server
	RSYSLOG_FORWARDING_CFG=
	if [ "$SYSLOG_REMOTE_ENABLED" = 'true' ]; then
		# TODO: Wait for remote syslog
		#awaitSuccess "Waiting for remote syslog UDP server $SYSLOG_HOST:$SYSLOG_PORT" nc -uzvw1 "$SYSLOG_HOST" "$SYSLOG_PORT" 2>/dev/null
		RSYSLOG_FORWARDING_CFG="*.* @$SYSLOG_HOST:$SYSLOG_PORT"
	fi

	# Write rsyslog config
	cat > /etc/rsyslog.conf <<-EOF
		\$ModLoad imuxsock.so # provides local unix socket under /dev/log
		\$ModLoad omstdout.so # provides messages to stdout
		\$template stdoutfmt,"%syslogtag% %msg%\n" # light stdout format

		*.* :omstdout:;stdoutfmt # send everything to stdout
		$RSYSLOG_FORWARDING_CFG
	EOF
	[ $? -eq 0 ] || exit 1
	chmod 444 /etc/rsyslog.conf || exit 1

	# Start rsyslog
	(
		rsyslogd -n -f /etc/rsyslog.conf
		terminateGracefully # Terminate whole container if syslogd somehow terminates
	) &
	awaitSuccess 'Waiting for local rsyslog' [ -S /dev/log ]
	rm -rf $INSTANCE_LOG_DIR/*
}

backup() {
	if [ ! "$1" ]; then echo "Usage: backup BACKUPFILE (tar.bz2)" >&2; return 1; fi
	if [ -f "$1" ] || [ -d "$1" ]; then echo "Backup destination file $1 already exists" >&2; return 1; fi
	ERROR=0
	BACKUP_ID="ldap_${INSTANCE_ID}_$(date +'%y-%m-%d_%H-%M-%S')"
	BACKUP_TMP_DIR=/tmp/$BACKUP_ID
	mkdir -p $(dirname $1) &&
	mkdir -p "$BACKUP_TMP_DIR" &&
	chmod -R 770 "$BACKUP_TMP_DIR" &&
	chown -R root:nobody "$BACKUP_TMP_DIR" || return 1
	for DB_NAME in $(find /var/lib/dirsrv/slapd-$INSTANCE_ID/db/ -mindepth 1 -maxdepth 1 -type d | xargs -n 1 basename); do
		ns-slapd db2ldif -D /etc/dirsrv/slapd-$INSTANCE_ID -n $DB_NAME -a "$BACKUP_TMP_DIR/$INSTANCE_ID-$DB_NAME.ldif" || ERROR=$?
	done
	(cd /tmp && tar cjf "$1" $BACKUP_ID)
	ERROR=$?
	rm -rf $BACKUP_TMP_DIR
	[ "$ERROR" -eq 0 ]
}

restore() {
	if [ ! "$1" ]; then echo "Usage: restore BACKUPFILE (tar.bz2)" >&2; exit 1; fi
	if [ ! -f "$1" ]; then echo "Backup file $1 does not exist" >&2; exit 1; fi
	if [ "$(slapdPID)" ]; then echo "You must terminate ns-slapd before you can restore dump" >&2; exit 1; fi
	setupDirsrvInstance # Install if directory doesn't exist
	EXTRACT_DIR=$(mktemp -d)
	(cd $EXTRACT_DIR && tar xjf "$1") || exit $?
	BACKUP_DIR="$EXTRACT_DIR/$(ls $EXTRACT_DIR)"
	chown -R root:nobody $EXTRACT_DIR && chmod -R 770 $EXTRACT_DIR
	ERROR=0
	for LDIF in $(ls "$BACKUP_DIR" | grep -E '\.ldif$'); do
		NAMES=$(echo $LDIF | sed -e 's/\.ldif$//')
		DB_NAME=$(echo $NAMES | cut -d - -f 2)
		ns-slapd ldif2db -D /etc/dirsrv/slapd-$INSTANCE_ID -n $DB_NAME -i "$BACKUP_DIR/$LDIF" || exit 1
	done
	rm -rf $EXTRACT_DIR
	return $ERROR
}

slapdPID() {
	ps h -o pid -C ns-slapd
}

terminateGracefully() {
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Disable termination call on signal to avoid infinite recursion
	for PID in $(slapdPID) $(ps h -o pid -C rsyslogd); do
		kill "$PID" 2>/dev/null
		while [ ! -z "$PID" ] && ps "$PID" >/dev/null; do
			sleep 1
		done
	done
}

case "$1" in
	ns-slapd|ldapmodify|ldapadd|ldapdelete|ldapsearch)
		[ $(ps aux | grep -c '') -le 5 ] && rm -f /var/run/syslogd.pid # Removes old syslog pid on container start
		setupDirsrvInstance # Installs if directory doesn't exist
		startRsyslog # Starts if not started
		CMD="$1"
		shift
		SLAPD_ARGS=
		if [ "$CMD" = ns-slapd ]; then
			SLAPD_ARGS=$@
			[ ! "$(slapdPID)" ] || (echo "ns-slapd is already running" >&2; false) || exit 1
		fi
		if [ ! "$(slapdPID)" ]; then
			[ ! "$FIRST_START" -a ! "$LDAP_INSTALL_BACKUP_FILE" ] || restore "$LDAP_INSTALL_BACKUP_FILE" || exit 1
			ns-slapd -D "$INSTANCE_DIR" $SLAPD_ARGS || exit $?
			setupSlapdLogging || exit 1
			setupSystemUsers || exit 1
		fi

		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM # Register signal handler for graceful shutdown

		if [ "$CMD" = ns-slapd ]; then # LDAP operations
			wait
		else
			waitForTcpService localhost $LDAP_SERVER_PORT
			"$CMD" $LDAP_OPTS $@
			terminateGracefully
		fi
	;;
	backup)
		$@
	;;
	*)
		exec "$@"
	;;
esac
