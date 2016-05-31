#!/bin/sh

set -e
	: ${LDAP_SERVER_PORT:=389}
	: ${LDAP_ADMIN_DOMAIN:=$(hostname -d)}
	: ${LDAP_ROOT_DN:='cn=dirmanager'}
	: ${LDAP_ROOT_DN_PWD:='Secret123'}
	: ${LDAP_SUFFIX:=$(echo "dc=$LDAP_ADMIN_DOMAIN" | sed 's/\./,dc=/g')}
LDAP_OPTS="-x -h localhost -p $LDAP_SERVER_PORT -D $LDAP_ROOT_DN -w $LDAP_ROOT_DN_PWD"

echo $LDAP_OPTS

usage() {
	echo "Usage: $0 {add LDIFFILE|modify LDIFFILE|delete SEARCHBASE|cat SEARCHBASE}" >&2
	case "$1" in delete|cat)
		echo "Did you mean $0 $1 ${LDAP_SUFFIX}?" >&2
		;;
	esac
	exit 1
}

[ $# -eq 2 ] || usage "$1"

case "$1" in
	modify)
		if [ ! -f "$2" ]; then
			echo "File '$2' does not exist!" >&2
			exit 1
		fi
		ldapmodify $LDAP_OPTS < "$2"
	;;
	add)
		if [ ! -f "$2" ]; then
			echo "File '$2' does not exist!" >&2
			exit 1
		fi
		ldapadd $LDAP_OPTS -f "$2"
	;;
	delete)
		ldapdelete $LDAP_OPTS -r "$2"
	;;
	cat)
		ldapsearch $LDAP_OPTS -b "$2" -LLL + *
	;;
	*)
		usage
	;;
esac
