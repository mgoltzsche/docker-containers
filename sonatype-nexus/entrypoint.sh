#!/bin/sh

export PLEXUS_NEXUS_WORK=/nexus-work

case "$1" in start|stop|console)
		gosu nexus /nexus/bin/nexus $1
	;;
	*)
		exec "$@"
	;;
esac
