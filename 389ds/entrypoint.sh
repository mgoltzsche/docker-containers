#!/bin/sh
FULL_MACHINE_NAME=$(hostname -f)
INSTANCE_ID=${INSTANCE_ID:=$(hostname -s)}
INSTANCE_DIR="/etc/dirsrv/slapd-$INSTANCE_ID"

NSSLAPD_LISTENHOST=${NSSLDAPD_LISTENHOST:=0.0.0.0}
NSSLAPD_PORT=${NSSLAPD_PORT:=389}
NSSLAPD_ROOTDN=${NSSLAPD_ROOTDN:='cn=dirmanager'}
NSSLAPD_ROOTPW=${NSSLAPD_ROOTPW:=Secret123}
NSSLAPD_ALLOW_ANONYMOUS_ACCESS=${NSSLAPD_ALLOW_ANONYMOUS_ACCESS:=off} # off|rootdse|on
NSSLAPD_ACCESSLOG_LOGGING_ENABLED=${NSSLAPD_ACCESSLOG_LOGGING_ENABLED:=on}
NSSLAPD_LOGGING_BACKEND=syslog
NSSLAPD_ACCESSLOG_LOGBUFFERING=off
# (Add any valid 389ds cn=config attribute as env var)

LDAP_OPTS=${LDAP_OPTS:=-x -h localhost -p "$NSSLAPD_PORT" -D "$NSSLAPD_ROOTDN" -w "$NSSLAPD_ROOTPW"}
LDAP_INSTALL_DOMAIN=${LDAP_INSTALL_DOMAIN:=$(hostname -d)}
LDAP_INSTALL_SUFFIX=${LDAP_INSTALL_SUFFIX:=$(echo "dc=$LDAP_INSTALL_DOMAIN" | sed 's/\./,dc=/g')}
LDAP_INSTALL_ADMIN_DOMAIN=${LDAP_INSTALL_ADMIN_DOMAIN:=$LDAP_INSTALL_DOMAIN}
LDAP_INSTALL_ADMIN_DOMAIN_SUFFIX=${LDAP_INSTALL_ADMIN_DOMAIN_SUFFIX:=$LDAP_INSTALL_SUFFIX}

checkContainer() {
	if [ -z "$NSSLAPD_ROOTPW" ] || [ "$NSSLAPD_ROOTPW" = 'Secret123' ]; then
		NSSLAPD_ROOTPW='Secret123'
		echo '####################################################' >&2
		echo '# WARN: No NSSLAPD_ROOTPW env var set.' >&2
		echo "# Using default password: '$NSSLAPD_ROOTPW'" >&2
		echo '####################################################' >&2
	fi
	if ! echo "$FULL_MACHINE_NAME" | grep -q '\.'; then
		echo "Set a fully qualified hostname. E.g. ldap.example.org" >&2
		exit 1
	fi
}

setupDirsrvInstance() {
	if [ -d "$INSTANCE_DIR" ]; then
		return 0 # Skip setup if already configured
	fi

	FIRST_START='true'

	set -e
	: ${LDAP_INSTALL_BACKUP_FILE:=}
	: ${LDAP_INSTALL_INF_FILE:=/tmp/ds-config.inf}
	: ${LDAP_INSTALL_LDIF_FILE:=suggest}
	: ${LDAP_INSTALL_CONFIG_DIRECTORY_ADMIN_ID:=admin}
	: ${LDAP_INSTALL_CONFIG_DIRECTORY_ADMIN_PW:=$NSSLAPD_ROOTPW}

	if [ -f "$LDAP_INSTALL_INF_FILE" ]; then
		echo "Installing LDAP server instance from configuration file $LDAP_INSTALL_INF_FILE"
	else
		echo "Installing new LDAP instance with:$(echo;set | grep -E '^LDAP_INSTALL_' | sed -E 's/(^[^=]+_PW=).+/\1***/' | xargs -n1 echo ' ')"
		cat > "$LDAP_INSTALL_INF_FILE" <<-EOF
			[General]
			FullMachineName= $FULL_MACHINE_NAME
			AdminDomain= $LDAP_INSTALL_ADMIN_DOMAIN
			SuiteSpotUserID= dirsrv
			SuiteSpotGroup= dirsrv
			ConfigDirectoryAdminID= $LDAP_INSTALL_CONFIG_DIRECTORY_ADMIN_ID
			ConfigDirectoryAdminPwd= $LDAP_INSTALL_CONFIG_DIRECTORY_ADMIN_PW

			[slapd]
			ServerIdentifier= $INSTANCE_ID
			ServerPort= $NSSLAPD_PORT
			Suffix= $LDAP_INSTALL_SUFFIX
			RootDN= $NSSLAPD_ROOTDN
			RootDNPwd= $NSSLAPD_ROOTPW
			InstallLdifFile= $LDAP_INSTALL_LDIF_FILE
		EOF
		[ $? -eq 0 ] || exit 1
	fi

    # Disable SELinux (taken from https://github.com/ioggstream/dockerfiles/blob/master/389ds/tls/entrypoint.sh)
    rm -fr /usr/lib/systemd/system
    sed -i 's/updateSelinuxPolicy($inf);//g' /usr/lib64/dirsrv/perl/*
    sed -i '/if (@errs = startServer($inf))/,/}/d' /usr/lib64/dirsrv/perl/*

	# Install LDAP server with config file
	setup-ds.pl -sdf "$LDAP_INSTALL_INF_FILE" &&
	rm -rf /tmp/ds-config.inf "/var/log/dirsrv/slapd-$INSTANCE_ID/*" 2>/dev/null || exit 1
}

# Sets an instance config property (doesn't work if ns-slapd is running)
setDseConfigAttr() {
	if grep -q "^$1:.*" "$INSTANCE_DIR/dse.ldif"; then
		# Update config attribute (using perl to replace multiline attributes)
		perl -i -p0e "s/\n$1:.*?\n([^ ]|\n|\$)/\n$1: $2\n\1/s" "$INSTANCE_DIR/dse.ldif"
	else
		# Add config attribute
		sed -i "/^nsslapd-port: .*/a$1: $2" "$INSTANCE_DIR/dse.ldif"
	fi
}

configureInstance() {
	NSSLAPD_ROOTPW="$(pwdhash -s ssha512 "$NSSLAPD_ROOTPW")"
	echo "Configuring LDAP instance with: $(echo; set | grep -E '^NSSLAPD_' | sed -E 's/(^[^=]+(_ROOTPW)=).+/\1***/' | xargs -n1 echo ' ')"
	for CFG_VAR in $(set | grep -Eo '^NSSLAPD_[^=]+'); do
		CFG_KEY="$(echo -n "$CFG_VAR" | tr '[:upper:]' '[:lower:]' | tr _ -)"
		CFG_VALUE="$(eval "echo \"\$$CFG_VAR\"" | sed 's/\//\\\//g')"
		setDseConfigAttr "$CFG_KEY" "$CFG_VALUE" || return 1
	done
}

configureSystemUsers() {
	LDAP_USERS="$(set | grep -Eo '^LDAP_USER_DN_[^=]+' | sed 's/^LDAP_USER_DN_//')"

	if [ "$LDAP_USERS" ]; then
		# Start local ns-slapd to configure users quietly
		setDseConfigAttr nsslapd-listenhost 127.0.0.1 &&
		setDseConfigAttr nsslapd-accesslog-logging-enabled off &&
		startDirsrv &&
		waitForTcpService localhost $NSSLAPD_PORT

		# Configure users
		for LDAP_USER_KEY in $LDAP_USERS; do
			LDAP_USER_DN="$(eval "echo \"\$LDAP_USER_DN_$LDAP_USER_KEY\"")"
			LDAP_USER_PASSWORD="$(eval "echo \"\$LDAP_USER_PW_$LDAP_USER_KEY\"")"
			LDAP_USER_PW_HASH=$(pwdhash -s ssha512 "$LDAP_USER_PASSWORD" | base64 - | xargs | sed 's/ /\n /')
			LDAP_USER_PREFIX=$(echo "$LDAP_USER_DN" | grep -Pio '^[a-z]+=[a-z0-9_\- ]+(?=,)' | sed 's/=/: /')
			LDAP_USER_EMAIL=$(eval "echo \"\$LDAP_USER_EMAIL_$LDAP_USER_KEY\"")
			LDAP_USER_EMAIL=${LDAP_USER_EMAIL:-$(echo "$LDAP_USER_PREFIX" | grep -Po '(?<=: ).*')"@service.$LDAP_INSTALL_DOMAIN"}

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

		# Terminate local ns-slapd and reset host and access log config
		terminatePid $(slapdPID)
		setDseConfigAttr nsslapd-listenhost "$NSSLAPD_LISTENHOST" &&
		setDseConfigAttr nsslapd-accesslog-logging-enabled "$NSSLAPD_ACCESSLOG_LOGGING_ENABLED" || exit 1
	fi
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

startRsyslog() {
	ps -C rsyslogd >/dev/null && return 1
	# Configure syslog forwarding and wait for remote syslog server
	RSYSLOG_FORWARDING_CFG=
	if [ "$SYSLOG_FORWARDING_ENABLED" = 'true' ]; then
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
	rm -f /var/run/syslogd.pid
	(
		rsyslogd -n -f /etc/rsyslog.conf
		terminateGracefully # Terminate whole container if syslogd somehow terminates
	) &
	awaitSuccess 'Waiting for local rsyslog' [ -S /dev/log ]
}

startDirsrv() {
	ns-slapd -D "$INSTANCE_DIR" -i /var/run/dirsrv/ns-slapd.pid $@
}

backup() {
	([ "$1" ] || (echo "Usage: backup BACKUPFILE (tar.bz2)" >&2; false)) &&
	(([ ! -f "$1" ] && [ ! -d "$1" ]) || (echo "Backup destination file $1 already exists" >&2; false)) || exit 1
	ERROR=0
	BACKUP_ID="ldap_${INSTANCE_ID}_$(date +'%y-%m-%d_%H-%M-%S')"
	BACKUP_TMP_DIR=/tmp/$BACKUP_ID
	mkdir -p $(dirname $1) &&
	mkdir -p "$BACKUP_TMP_DIR" &&
	chmod -R 770 "$BACKUP_TMP_DIR" &&
	chown -R root:dirsrv "$BACKUP_TMP_DIR" || return 1
	for DB_NAME in $(find /var/lib/dirsrv/slapd-$INSTANCE_ID/db/ -mindepth 1 -maxdepth 1 -type d | xargs -n 1 basename); do
		ns-slapd db2ldif -D /etc/dirsrv/slapd-$INSTANCE_ID -n $DB_NAME -a "$BACKUP_TMP_DIR/$INSTANCE_ID-$DB_NAME.ldif" || ERROR=$?
	done
	tar -cjvf "$1" -C /tmp $BACKUP_ID
	ERROR=$?
	rm -rf $BACKUP_TMP_DIR
	return $ERROR
}

restore() {
	([ "$1" ] || (echo "LDAP_INSTALL_BACKUP_FILE (tar.bz2) not set" >&2; false)) &&
	([ -f "$1" ] || (echo "Backup file $1 does not exist" >&2; false)) &&
	(! ps -C ns-slapd >/dev/null || (echo "You must terminate ns-slapd before you can restore dump" >&2; false)) || exit 1
	echo "Restoring backup $1"
	setupDirsrvInstance # Install if directory doesn't exist
	EXTRACT_DIR=$(mktemp -d)
	tar -xjvf "$1" -C $EXTRACT_DIR || exit $?
	BACKUP_DIR="$EXTRACT_DIR/$(ls $EXTRACT_DIR | head -1)"
	chown -R root:dirsrv $EXTRACT_DIR && chmod -R 770 $EXTRACT_DIR
	ERROR=0
	for LDIF in $(ls "$BACKUP_DIR" | grep -E '\.ldif$'); do
		NAMES=$(echo $LDIF | sed -e 's/\.ldif$//')
		FOUND_LDIF=true
		DB_NAME=$(echo $NAMES | cut -d - -f 2)
		ns-slapd ldif2db -D /etc/dirsrv/slapd-$INSTANCE_ID -n $DB_NAME -i "$BACKUP_DIR/$LDIF" || exit 1
	done
	rm -rf $EXTRACT_DIR
	[ "$FOUND_LDIF" ] || (echo "Invalid backup format"; false) || return 1
	return $ERROR
}

slapdPID() {
	cat /var/run/dirsrv/ns-slapd.pid 2>/dev/null
}

terminatePid() {
	kill "$1" 2>/dev/null
	while [ ! -z "$1" ] && ps "$1" >/dev/null; do
		sleep 1
	done
}

terminateGracefully() {
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Disable termination call on signal to avoid infinite recursion
	for PID in $(slapdPID) $(ps h -o pid -C rsyslogd); do
		terminatePid "$PID"
	done
}

case "$1" in
	ns-slapd|ldapmodify|ldapadd|ldapdelete|ldapsearch)
		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM # Register signal handler for graceful shutdowns
		CMD="$1"
		shift
		SLAPD_ARGS=
		if [ "$CMD" = ns-slapd ]; then
			SLAPD_ARGS=$@
			! ps -C ns-slapd >/dev/null || (echo "ns-slapd is already running" >&2; false) || exit 1
			rm -f /var/run/dirsrv/ns-slapd.pid
		fi
		checkContainer
		setupDirsrvInstance # Installs if directory doesn't exist
		startRsyslog # Starts if not started
		if ! ps -C ns-slapd >/dev/null; then
			rm -f /var/log/dirsrv/slapd-ldap/*
			([ ! "$FIRST_START" -o ! "$LDAP_INSTALL_BACKUP_FILE" ] || restore "$LDAP_INSTALL_BACKUP_FILE") &&
			configureInstance &&
			configureSystemUsers &&
			startDirsrv $SLAPD_ARGS || exit 1
		fi

		if [ "$CMD" = ns-slapd ]; then
			# LDAP server started - wait
			wait
		else
			# LDAP operations
			waitForTcpService localhost $NSSLAPD_PORT
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
