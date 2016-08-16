#!/bin/sh

export PATH="$PATH:/nexus/bin/"

case "$1" in
	nexus)
		chown -R nexus:nexus /data &&
		gosu nexus $@
	;;
	*)
		exec "$@"
	;;
esac
