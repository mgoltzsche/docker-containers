#!/bin/sh

export PLEXUS_NEXUS_WORK=/data
export PATH="$PATH:/nexus/bin/"

case "$1" in
	nexus)
		gosu nexus $@
	;;
	*)
		exec "$@"
	;;
esac
