#!/bin/sh

SYSLOG_ENABLED=${SYSLOG_ENABLED:=false}
SYSLOG_HOST=${SYSLOG_HOST:=logstash}
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
		# Create initial database directory
		FIRST_START='true'
		echo "Setting up initial database in $PGDATA"
		eval "gosu postgres initdb $PG_INITDB_ARGS" || exit 1
	fi

	# Start postgres locally for user and DB setup or migration
	gosu postgres postgres -c listen_addresses=localhost &
	#POSTGRES_PID=$!

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

	terminatePostgres
}

startRsyslog() {
	# Wait until syslog server is available to capture log
	awaitSuccess "Waiting for syslog UDP server $SYSLOG_HOST:$SYSLOG_PORT" nc -uzvw1 "$SYSLOG_HOST" "$SYSLOG_PORT"

	cat > /etc/rsyslog.conf <<-EOF
		\$ModLoad imuxsock.so # provides support for local system logging (e.g. via logger command)
		\$ModLoad omstdout.so # provides messages to stdout

		*.* :omstdout: # send everything to stdout
		*.* @$SYSLOG_HOST:$SYSLOG_PORT
	EOF
	[ $? -eq 0 ] || exit 1
	chmod 444 /etc/rsyslog.conf || exit 1

	# Start rsyslog to collect logs
	rsyslogd -n -f /etc/rsyslog.conf &
	SYSLOG_PID=$!
	awaitSuccess 'Waiting for local rsyslog' [ -S /dev/log ]
}

postgresPid() {
	ps -o pid,comm | grep -Em1 '^\s*\d+\s+(gosu\s+)?postgres' | grep -Eo '\d+'
}

isProcessTerminated() {
	! ps -o pid | grep -q ${1:-0}
}

awaitTermination() {
	awaitSuccess '' isProcessTerminated $1
}

terminatePostgres() {
	while [ "$(postgresPid)" ]; do
		POSTGRES_PID=$(postgresPid)
		kill $POSTGRES_PID 2>/dev/null
		awaitTermination $POSTGRES_PID
	done
}

terminateRsyslog() {
	kill $SYSLOG_PID 2>/dev/null
	awaitTermination $SYSLOG_PID
}

terminateGracefully() {
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Disable termination call on signal to avoid infinite recursion
	terminatePostgres
	terminateRsyslog
	exit 0
}

isPostgresSpawned() {
	$CHILD_PID
	ps -o comm | grep -Eq '^postgres$'
}

# Register signal handler for orderly shutdown
trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM

if [ "$1" = 'postgres' ]; then
	setupPostgres
	[ ! "$SYSLOG_ENABLED" = 'true' ] || startRsyslog
	(
		gosu postgres $@
		terminateRsyslog
	) &
	wait
else
	exec "$@"
fi
