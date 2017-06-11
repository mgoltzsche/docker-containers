#!/bin/sh

awaitSuccess() {
	MSG="$1"
	shift
	until $@ >/dev/null 2>/dev/null; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 3
	done
}

processTerminated() {
	! ps -o pid | grep -wq ${1:-0}
}

awaitTermination() {
	awaitSuccess "" processTerminated $1
}

terminateGracefully() {
	trap : SIGHUP SIGINT SIGQUIT SIGTERM
	kill $MAGNOLIA_PID 2>/dev/null
	awaitTermination $MAGNOLIA_PID
	exit 0
}

case "$1" in
	run)
		/opt/magnolia/bin/catalina.sh run &
		MAGNOLIA_PID=$!
		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM
		wait
	;;
	sh)
		$@
	;;
	*)
		echo "Usage: run|sh" >&2
	;;
esac
