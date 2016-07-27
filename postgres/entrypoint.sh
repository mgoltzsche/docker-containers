#!/bin/sh

SYSLOG_REMOTE_ENABLED=${SYSLOG_REMOTE_ENABLED:=false}
SYSLOG_HOST=${SYSLOG_HOST:=syslog}
SYSLOG_PORT=${SYSLOG_PORT:=514}

awaitSuccess() {
	MSG="$1"
	shift
	until $@ >/dev/null 2>/dev/null; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 1
	done
}

isPostgresStarted() {
	ps -o pid | grep -Eq "^\s*$1\$" || exit 1
	gosu postgres psql -c 'SELECT 1'
}

setupPostgres() {
	FIRST_START=
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
		# Create initial database directory (enforcing authentication in TCP connections)
		FIRST_START='true'
		echo "Setting up initial database in $PGDATA"
		eval "gosu postgres initdb $PG_INITDB_ARGS --auth-host=md5" || exit 1
	fi

	# Start postgres locally for user and DB setup
	gosu postgres postgres -c listen_addresses=localhost &

	# Wait for postgres start
	awaitSuccess 'Waiting for local postgres to start before setup' isPostgresStarted $!
	echo 'Setting up users and DBs ...'

	# Check and set default postgres user password if undefined
	if [ ! "$PG_USER_POSTGRES" ]; then
		export PG_USER_POSTGRES=Secret123
		echo "WARNING: No postgres user password configured. Using '$PG_USER_POSTGRES'. Set PG_USER_POSTGRES to remove this warning" >&2
	fi

	for PG_USER_KEY in $(set | grep -Eo '^PG_USER_[^=]+' | sed 's/^PG_USER_//'); do
		PG_USER=$(echo -n "$PG_USER_KEY" | tr '[:upper:]' '[:lower:]') # User name lower case
		PG_USER_PASSWORD=$(eval "echo \$PG_USER_$PG_USER_KEY")
		PG_USER_DATABASE="$PG_USER"
		# Create user
		if ! gosu postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'" | grep -q 1; then
			echo "Adding PostgreSQL user: $PG_USER"
			gosu postgres createuser -E "$PG_USER" || exit 1
		else
			echo "Resetting PostgreSQL user's password: $PG_USER"
		fi
		# Reset user password
		gosu postgres psql -c "ALTER USER $PG_USER WITH ENCRYPTED PASSWORD '$PG_USER_PASSWORD'" >/dev/null || exit 1
		# Create user database
		if ! gosu postgres psql -lqt | cut -d \| -f 1 | grep -qw "$PG_USER_DATABASE"; then
			echo "Adding PostgreSQL database: $PG_USER_DATABASE"
			gosu postgres createdb -T template0 -O "$PG_USER" "$PG_USER_DATABASE" || exit 1
		fi
	done

	# Run init scripts
	if [ "$FIRST_START" ]; then
		if [ "$(ls /entrypoint-initdb.d/)" ]; then
			echo "Running init scripts:"
			for f in /entrypoint-initdb.d/*; do
				case "$f" in
					*.sh)     echo "  Running $f"; . "$f" 2>&1 | sed 's/^/    /g' || exit 1 ;;
					*.sql)    echo "  Running $f"; gosu psql < "$f" 2>&1 | sed 's/^/    /g' || exit 1 ;;
					*.sql.gz) echo "  Running $f"; gunzip -c "$f" | gosu psql 2>&1 | sed 's/^/    /g' || exit 1 ;;
					*)        echo "  Ignoring $f" ;;
				esac
			done
		else
			echo 'No initscripts found in /entrypoint-initdb.d. Put *.sh, *.sql or *.sql.gz files there to initialize DB with on first start'
		fi
	fi

	terminatePid $(postgresPid)
}

backup() {
	# TODO: secure db access via this server especially for postgres user
	if [ $# -eq 0 ]; then
		read DB_DATABASE
		read DB_USERNAME
		read DB_PASSWORD
	elif [ $# -eq 3 ]; then
		DB_DATABASE="$1"
		DB_USERNAME="$2"
		DB_PASSWORD="$3"
	else
		echo "Usage: backup DATABASE USERNAME PASSWORD" >&2
		return 1
	fi
	echo "Dumping database $DB_DATABASE" >&2
	# Dump via TCP to enforce authentication
	export PGPASSWORD="$DB_PASSWORD"
	pg_dump -h localhost -p 5432 -U "$DB_USERNAME" \
		--inserts --blobs --no-tablespaces --no-owner --no-privileges \
		--disable-triggers --disable-dollar-quoting --serializable-deferrable \
		"$DB_DATABASE"
	unset PGPASSWORD
}

startBackupServer() {
	# Backup server required because pg_dump must be of same version as postgres
	# which may not be available in most other containers (e.g. redmine).
	# ATTENTION: Use backup server only in local net since it is unencrypted.
	echo "Starting backup server on port 5433"
	nc -lk -s 0.0.0.0 -p 5433 -e /entrypoint.sh backup &
	BACKUP_SERVER_PID=$!
}

backupClient() {
	# TODO: check for line '-- PostgreSQL database dump complete'
	printf 'redmine\nredmine\nredminesecret' | nc -w 3 localhost 5433
}

startRsyslog() {
	SYSLOG_FORWARDING_CFG=
	if [ "$SYSLOG_REMOTE_ENABLED" = 'true' ]; then
		awaitSuccess "Waiting for syslog UDP server $SYSLOG_HOST:$SYSLOG_PORT" nc -uzvw1 "$SYSLOG_HOST" "$SYSLOG_PORT"
		SYSLOG_FORWARDING_CFG="*.* @$SYSLOG_HOST:$SYSLOG_PORT"
	fi

	cat > /etc/rsyslog.conf <<-EOF
		\$ModLoad imuxsock.so # provides local unix socket under /dev/log
		\$ModLoad omstdout.so # provides messages to stdout
		\$template stdoutfmt,"%syslogtag% %msg%\n" # light stdout format

		*.* :omstdout:;stdoutfmt # send everything to stdout
		$SYSLOG_FORWARDING_CFG
	EOF
	[ $? -eq 0 ] || exit 1
	chmod 444 /etc/rsyslog.conf || exit 1

	# Start rsyslog to collect logs
	rsyslogd -n -f /etc/rsyslog.conf &
	SYSLOG_PID=$!
	awaitSuccess 'Waiting for local rsyslog' [ -S /dev/log ]
}

postgresPid() {
	cat "$PGDATA/postmaster.pid" 2>/dev/null | head -1
}

isProcessTerminated() {
	! ps -o pid | grep -wq ${1:-0}
}

awaitTermination() {
	awaitSuccess '' isProcessTerminated $1
}

terminatePid() {
	kill $1 2>/dev/null
	awaitTermination $1
}

terminateGracefully() {
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Disable termination call on signal to avoid infinite recursion
	terminatePid $BACKUP_SERVER_PID
	terminatePid $(postgresPid)
	terminatePid $SYSLOG_PID
	exit 0
}

isPostgresSpawned() {
	ps -o comm | grep -Eq '^postgres$'
}

case "$1" in
	postgres)
		# Register signal handler for orderly shutdown
		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM || exit 1
		startRsyslog
		setupPostgres
		if ! isProcessTerminated "$(postgresPid)"; then
			echo 'Postgres is already running' >&2
			exit 1
		fi
		(
			gosu postgres $@
			terminateGracefully
		) &
		startBackupServer
		wait
	;;
	backup)
		$@ || exit $?
	;;
	*)
		exec "$@"
	;;
esac
