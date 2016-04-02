#!/bin/sh

DOMAIN=$(hostname -d)
LDAP_SUFFIX='dc='$(echo -n "$DOMAIN" | sed s/\\./,dc=/g)
LDAP_USER_DN="cn=vmail,ou=Special Users,$LDAP_SUFFIX"
LDAP_PASSWORD="asdf"
LDAP_SEARCH_BASE="ou=Domains,$LDAP_SUFFIX"

cd "$(dirname $0)"

# postfix LDAP configuration files
DOVECOT_LDAP_CONF=$(./rendertpl.sh dovecot/dovecot-ldap.conf.ext.tpl \
	HOST=ldap PORT=10389 \
	USER_DN="$LDAP_USER_DN" PASSWORD="$LDAP_PASSWORD" \
	SEARCH_BASE="$LDAP_SEARCH_BASE"
) || exit 1

cat dovecot/dovecot.conf > /etc/dovecot/dovecot.conf &&
cd /etc/dovecot &&
echo "$DOVECOT_LDAP_CONF" > dovecot-ldap.conf.ext

if [ ! -f dovecot-ldap-userdb.conf.ext ]; then # link ldap conf as user db if not linked already
	ln -s /etc/dovecot/dovecot-ldap.conf.ext dovecot-ldap-userdb.conf.ext || exit 1
fi

chmod 600 dovecot-ldap.conf.ext
