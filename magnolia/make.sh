#!/bin/sh

case "$1" in
	build)
		docker build -t algorythm/magnolia:latest --rm .
	;;
	run)
		docker run -p 8080:8080 -h magnolia-eval algorythm/magnolia:latest
	;;
	logs)
		docker logs `docker ps | grep magnolia | cut -d ' ' -f 1`
	;;
	sh)
		docker run -it -h magnolia-eval algorythm/magnolia:latest sh
	;;
	join)
		docker exec -it `docker ps | grep algorythm/magnolia | cut -d ' ' -f 1` sh
	;;
	kill)
		docker kill `docker ps | grep algorythm/magnolia | cut -d ' ' -f 1`
	;;
	*)
		echo "Usage: $0 build|run|logs|sh|join|kill" >&2
		exit 1
	;;
esac
