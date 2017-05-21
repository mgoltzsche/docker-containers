#!/bin/sh

[ $(id -u) -eq 0 ] || echo 'You may have to run the script as root!' >&2

case "$1" in
	build)
		docker build -t algorythm/sonatype-nexus:latest --rm .
	;;
	run)
		docker run -h repository.algorythm.de -p 8081:8081 algorythm/sonatype-nexus:latest
	;;
	karaf-console)
		# Press enter after it has been started
		# If you want to reset your password see: https://support.sonatype.com/hc/en-us/articles/213467158-How-to-reset-a-default-password-in-Nexus-3-x-using-the-Karaf-Console
		docker run -it -h repository.algorythm.de -p 8081:8081 algorythm/sonatype-nexus:latest karaf-console
	;;
	sh)
		docker run -it -h repository.algorythm.de algorythm/sonatype-nexus:latest sh
	;;
	join)
		docker exec -it `docker ps | grep algorythm/sonatype-nexus | cut -d ' ' -f 1` /bin/sh
	;;
	*)
		echo "Usage $0 build|run|karaf-console|sh|join"
		exit 1
	;;
esac
