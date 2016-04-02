#!/bin/sh

DOMAIN=$(hostname -d)
LDAP_SUFFIX='dc='$(echo -n "$DOMAIN" | sed s/\\./,dc=/g)
LDAP_USER_DN="cn=vmail,ou=Special Users,$LDAP_SUFFIX"
LDAP_PASSWORD="asdf"
LDAP_DOMAIN_SEARCH_BASE="ou=Domains,$LDAP_SUFFIX"
LDAP_DOMAIN_QUERY='(associatedDomain=%s)'
LDAP_DOMAIN_ATTR='associatedDomain'
LDAP_MAILBOX_SEARCH_BASE="$LDAP_SUFFIX"
LDAP_MAILBOX_QUERY='(&(objectClass=inetOrgPerson)(|(mail=%s)(mailAlternateAddress=%s)))'

cd "$(dirname $0)"

# main postfix configuration file
MAIN_CF=$(./rendertpl.sh postfix/main.cf.tpl MACHINE_FQN=$(hostname -f))

# postfix LDAP configuration files
LDAP_DOMAINS_CF=$(./rendertpl.sh postfix/ldap.cf.tpl \
	HOST=ldap PORT=10389 \
	USER_DN="$LDAP_USER_DN" PASSWORD="$LDAP_PASSWORD" \
	SEARCH_BASE="$LDAP_DOMAIN_SEARCH_BASE" \
	QUERY_FILTER="$LDAP_DOMAIN_QUERY" \
	RESULT_ATTRIBUTE="$LDAP_DOMAIN_ATTR"
) || exit 1

LDAP_ALIASES_CF=$(./rendertpl.sh postfix/ldap.cf.tpl \
	HOST=ldap PORT=10389 \
	USER_DN="$LDAP_USER_DN" PASSWORD="$LDAP_PASSWORD" \
	SEARCH_BASE="$LDAP_MAILBOX_SEARCH_BASE" \
	QUERY_FILTER="$LDAP_MAILBOX_QUERY" \
	RESULT_ATTRIBUTE=mailForwardingAddress
) || exit 1

LDAP_MAILBOXES_CF=$(./rendertpl.sh postfix/ldap.cf.tpl \
	HOST=ldap PORT=10389 \
	USER_DN="$LDAP_USER_DN" PASSWORD="$LDAP_PASSWORD" \
	SEARCH_BASE="$LDAP_MAILBOX_SEARCH_BASE" \
	QUERY_FILTER="$LDAP_MAILBOX_QUERY" \
	RESULT_ATTRIBUTE='mail\nresult_format = %d/%u/'
) || exit 1

LDAP_SENDERS_CF=$(./rendertpl.sh postfix/ldap.cf.tpl \
	HOST=ldap PORT=10389 \
	USER_DN="$LDAP_USER_DN" PASSWORD="$LDAP_PASSWORD" \
	SEARCH_BASE="$LDAP_MAILBOX_SEARCH_BASE" \
	QUERY_FILTER="$LDAP_MAILBOX_QUERY" \
	RESULT_ATTRIBUTE=mail
) || exit 1

# Enable submission (authenticated mail submission) and smtps according to http://wiki.alpinelinux.org/wiki/ISP_Mail_Server_HowTo
if [ $(grep -c '^submission' /etc/postfix/master.cf) -eq 0 ]; then
cat >> /etc/postfix/master.cf <<EOF
submission inet n       -       n       -       -       smtpd
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF
fi
if [ $(grep -c '^smtps' /etc/postfix/master.cf) -eq 0 ]; then
cat >> /etc/postfix/master.cf <<EOF
smtps     inet  n       -       n       -       -       smtpd
  -o smtpd_tls_security_level=encrypt
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF
fi

cd /etc/postfix &&
mkdir -p ldap &&
chmod 00755 ldap &&
echo "$MAIN_CF"           > main.cf &&
echo "$LDAP_DOMAINS_CF"   > ldap/virtual_domains.cf &&
echo "$LDAP_ALIASES_CF"   > ldap/virtual_aliases.cf &&
echo "$LDAP_MAILBOXES_CF" > ldap/virtual_mailboxes.cf &&
echo "$LDAP_SENDERS_CF"   > ldap/virtual_senders.cf &&
chmod 640 ldap/*.cf &&
chown root:postfix ldap/*.cf
newaliases
