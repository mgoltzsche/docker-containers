#!/bin/sh

# Runs the provided command until it succeeds.
# Takes the error message to be displayed if it doesn't succeed as first argument.
awaitSuccess() {
	MSG="$1"
	shift
	until $@ >/dev/null 2>/dev/null; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 1
	done
}

# Terminates the provided PID and waits until it is terminated
terminatePid() {
	kill $1 2>/dev/null
	awaitSuccess '' isProcessTerminated $1
}

# Tests if the provided PID is terminated
isProcessTerminated() {
	! ps ${1:-0} >/dev/null
}

# Terminates the whole container orderly
terminateGracefully() {
	trap : 1 2 3 15 # Unregister signal handler to avoid infinite recursion
	terminatePid $HHVM_PID
	terminatePid $LOG_PIPE_LOOP_PID
	terminatePid $(ps -o pid -C 'cat /var/log/hhvm/error.log' | tail -1)
	terminatePid $SYSLOG_PID
	exit 0
}

setServerProp() {
	KEY=$(echo "$1" | grep -Eo '^\s*[^;= ]+')
	KEY_ESC=$(echo "$KEY" | sed 's/\./\\./g')
	sed -Ei "/\s*$KEY_ESC/d" /etc/hhvm/server.ini # Remove property from file
	echo "$KEY = $2" >> /etc/hhvm/server.ini # Add property to file
}

# Starts a local syslog server to collect (and forward) HHVM/PHP logs.
startRsyslog() {
	echo "Starting rsyslogd ..."
	rm -f /var/run/rsyslogd.pid || exit 1
	SYSLOG_FORWARDING_CFG=
	if [ "$SYSLOG_FORWARDING_ENABLED" = 'true' ]; then
		awaitSuccess "Waiting for syslog UDP server $SYSLOG_HOST:$SYSLOG_PORT" nc -uzvw1 "$SYSLOG_HOST" "$SYSLOG_PORT"
		SYSLOG_FORWARDING_CFG="*.* @$SYSLOG_HOST:$SYSLOG_PORT"
	fi

	cat > /etc/rsyslog.conf <<-EOF
		\$ModLoad imuxsock.so # provides local unix socket under /dev/log
		\$template stdoutfmt,"%syslogtag% %msg%\n" # light stdout format

		$SYSLOG_FORWARDING_CFG
		*.* /dev/stdout;stdoutfmt
	EOF
	[ $? -eq 0 ] &&
	chmod 444 /etc/rsyslog.conf || exit 1

	rsyslogd -n -f /etc/rsyslog.conf & # Run rsyslogd in background
	SYSLOG_PID=$!
	awaitSuccess 'Waiting for local rsyslog' [ -S /dev/log ]
}

#setServerProp hhvm.server.type proxygen
chown -R www-data:www-data /apps

# Rehash mounted ca certificates
c_rehash /etc/ssl/certs >/dev/null || exit 1

case "$1" in
	hhvm)
		! ps -C hhvm >/dev/null || (echo "HHVM already running" >&2; false) || exit 1
		trap terminateGracefully 1 2 3 15
		startRsyslog
		for INIT_SCRIPT in $(find /conf.d -name *.sh); do
			sh $INIT_SCRIPT || exit 1
		done
		rm -f /var/log/hhvm/error.log &&
		mkfifo /var/log/hhvm/error.log &&
		chown root:www-data /var/log/hhvm/error.log &&
		chmod 420 /var/log/hhvm/error.log || exit 1
		while true; do
			cat /var/log/hhvm/error.log # Log into named pipe since hhvm user cannot log into /dev/stderr
		done &
		LOG_PIPE_LOOP_PID=$!
		# TODO: handle PHP error_log if not already done by both processes piping in same pipe
		gosu www-data $@ &
		HHVM_PID=$!
		wait
	;;
	*)
		exec "$@"
	;;
esac
