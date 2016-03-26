#!/bin/dumb-init /bin/sh

if [ "$1" = 'run' ]; then
	cd /apacheds &&
	gosu apacheds /apacheds/bin/apacheds.sh run
elif [ "$1" = 'start' ]; then
	cd /apacheds &&
	gosu apacheds /apacheds/bin/apacheds.sh start
elif [ "$1" = 'stop' ]; then
	cd /apacheds &&
	gosu apacheds /apacheds/bin/apacheds.sh stop
elif [ "$1" = 'modify' ]; then
	cd /apacheds &&
	ldapmodify -x -h localhost -p 10389 -D uid=admin,ou=system -w secret < $2
else
    exec "$@"
fi
