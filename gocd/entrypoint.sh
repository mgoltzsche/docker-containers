#!/bin/sh

awaitSuccess() {
	MSG="$1"
	shift
	until $@; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 1
	done
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

# Register signal handler for orderly shutdown
#trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM

case "$1" in
	'/go-server/server.sh')
		echo "Starting Go server"
		gosu gocd $@
	;;
	backup|restore)
		$@
	;;
	*)
		exec $@
	;;
esac
