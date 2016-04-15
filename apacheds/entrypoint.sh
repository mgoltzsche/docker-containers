#!/bin/sh

LDAP_OPTS="-x -h localhost -p 10389 -D uid=admin,ou=system -w $(cat /etc/apachedspw)"

# TODO: Start apacheds with port 389.
# setcap does not work in docker container with aufs.
# Enable the following line when aufs supports capabilities.
#setcap 'CAP_NET_BIND_SERVICE=+ep' $(readlink -f $(which java))
# or add to docker-compose.yml service:
#     cap_add:
#      - CAP_NET_BIND_SERVICE

# Setup apacheds instance
/apacheds/bin/setup-instance.sh $LDAP_DOMAIN || exit 1

if [ "$1" = 'run' ]; then
	#/entrypoint-consul.sh client -retry-join=consul &
	cd /apacheds &&
	gosu apacheds /apacheds/bin/apacheds.sh run
	# Wait for ApacheDS to start
	#while [ $(netstat -tpln | grep -c :10389) -eq 0 ]; do
	#	sleep 1
	#done
	#/apacheds/bin/reset-admin-password.sh
	# Wait for ApacheDS and consul to terminate
	#wait
elif [ "$1" = 'start' ]; then
	cd /apacheds &&
	gosu apacheds /apacheds/bin/apacheds.sh start
elif [ "$1" = 'stop' ]; then
	cd /apacheds &&
	gosu apacheds /apacheds/bin/apacheds.sh stop
elif [ "$1" = 'modify' ]; then
	if [ ! -f "$2" ]; then
		echo "Usage: $0 modify LDIFFILE" >&2
		echo "File '$2' does not exist!" >&2
		exit 1
	fi
	ldapmodify $LDAP_OPTS < "$2"
elif [ "$1" = 'add' ]; then
	if [ ! -f "$2" ]; then
		echo "Usage: $0 add LDIFFILE" >&2
		echo "File '$2' does not exist!" >&2
		exit 1
	fi
	ldapadd $LDAP_OPTS -f "$2"
elif [ "$1" = 'delete' ]; then
	if [ "$2" = '' ]; then
		echo "Usage: $0 delete SEARCHBASE" >&2
		echo "Did you mean $0 delete dc=${LDAP_DOMAIN/./,dc=}?" >&2
		exit 1
	fi
	ldapdelete $LDAP_OPTS -r "$2"
elif [ "$1" = 'cat' ]; then
	SEARCHBASE="$2"
	if [ "$SEARCHBASE" = '' ]; then
		SEARCHBASE="dc=${LDAP_DOMAIN/./,dc=}"
	fi
	ldapsearch $LDAP_OPTS -b "$SEARCHBASE" -LLL + *
else
    exec "$@"
fi
