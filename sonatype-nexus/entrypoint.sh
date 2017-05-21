#!/bin/sh

export PATH="$PATH:/nexus/bin/"

case "$1" in
	nexus)
		sed -Ei 's/^(-Dkaraf.startLocalConsole)=.*/\1=false/' /nexus/bin/nexus.vmoptions &&
		chown nexus:nexus /data &&
		gosu nexus $@
	;;
	karaf-console)
		echo 'Press enter to start the karaf console after the application has been started' >&2
		echo 'If you want to reset your password see: https://support.sonatype.com/hc/en-us/articles/213467158-How-to-reset-a-default-password-in-Nexus-3-x-using-the-Karaf-Console' >&2
		sed -Ei 's/^(-Dkaraf.startLocalConsole)=.*/\1=true/' /nexus/bin/nexus.vmoptions &&
		chown nexus:nexus /data &&
		gosu nexus nexus run
	;;
	sh)
		$@
	;;
	*)
		echo "Usage: $0 nexus|karaf-console|sh" >&2
		exit 1
	;;
esac
