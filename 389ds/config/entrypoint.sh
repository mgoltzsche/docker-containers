#!/bin/bash

case "$1" in
	start)
		start-dirsrv
	;;
	stop)
		stop-dirsrv
	;;
	restart)
		restart-dirsrv
	;;
	bash)
		/bin/bash
	;;
	*)
		echo 'Usage: service dirsrv {start|stop|restart|bash}' >&2
		exit 3
	;;
esac

