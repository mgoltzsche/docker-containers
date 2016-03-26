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
else
    exec "$@"
fi
