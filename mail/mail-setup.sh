#!/bin/sh

DOMAIN=$(hostname -d)
LDAP_SUFFIX='dc='$(echo -n "$DOMAIN" | sed s/\\./,dc=/g)
LDAP_HOST=ldap.service.dc1.consul
LDAP_PORT=10389
LDAP_USER_DN="cn=vmail,ou=Special Users,$LDAP_SUFFIX"
LDAP_PASSWORD="asdf"
LDAP_MAILBOX_SEARCH_BASE="$LDAP_SUFFIX"
LDAP_DOMAIN_SEARCH_BASE="ou=Domains,$LDAP_SUFFIX"

if [ -z "$DOMAIN" ]; then # Terminate when domain name cannot be determined
	echo 'hostname -d is undefined.' >&2
	echo 'Setup a proper hostname by adding an entry to /etc/hosts like this:' >&2
	echo ' 172.17.0.2      mail.example.org mail' >&2
	echo 'When using docker start the container with the -h option' >&2
	echo 'to configure the hostname. E.g.: -h mail.example.org' >&2
	exit 1
fi

echo <<EOF
Configuring mailing with:
  DOMAIN:                   $DOMAIN
  LDAP_HOST:                $LDAP_HOST
  LDAP_PORT:                $LDAP_PORT
  LDAP_SUFFIX:              $LDAP_SUFFIX
  LDAP_USER_DN:             $LDAP_USER_DN
  LDAP_MAILBOX_SEARCH_BASE: $LDAP_MAILBOX_SEARCH_BASE
  LDAP_DOMAIN_SEARCH_BASE:  $LDAP_DOMAIN_SEARCH_BASE
EOF

setupSslCertificate() {
	# Generate SSL certificate if not available
	if [ ! -f "/etc/ssl/private/server.key" ]; then
		SUBJ="/C=DE/ST=Berlin/L=Berlin/O=algorythm/CN=$DOMAIN"
		echo "Generating new mail server certificate for '$SUBJ' ..."
		openssl req -new -newkey rsa:4096 -days 2000 -nodes -x509 -subj "$SUBJ" -keyout /etc/ssl/private/server.key -out /etc/ssl/certs/server.crt &&
		chmod 600 /etc/ssl/private/server.key
	fi
}

setupPostfix() {
	LDAP_DOMAIN_QUERY='(associatedDomain=%s)'
	LDAP_DOMAIN_ATTR='associatedDomain'
	LDAP_MAILBOX_QUERY='(&(objectClass=inetOrgPerson)(|(mail=%s)(mailAlternateAddress=%s)))'

	echo "Configuring postfix ..."
	MAIN_CF_TPL="$(cat /etc/postfix/main.cf.tpl)" &&
	mkdir -p /etc/postfix/ldap &&
	chmod 00755 /etc/postfix/ldap &&
	# Render main postfix configuration file with actual hostname
	echo "${MAIN_CF_TPL/\$\{MACHINE_FQN\}/$(hostname -f)}" > /etc/postfix/main.cf &&
	# Generate postfix LDAP configuration files
	cd /etc/postfix/ldap &&
	postfixLdapConf virtual_domains.cf   "$LDAP_DOMAIN_SEARCH_BASE"  "$LDAP_DOMAIN_QUERY"  "$LDAP_DOMAIN_ATTR" &&
	postfixLdapConf virtual_aliases.cf   "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" 'mailForwardingAddress' &&
	postfixLdapConf virtual_mailboxes.cf "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" "mail\nresult_format = %d/%u/" &&
	postfixLdapConf virtual_senders.cf   "$LDAP_MAILBOX_SEARCH_BASE" "$LDAP_MAILBOX_QUERY" 'mail' &&
	# Update postfix aliases DB
	newaliases
}

postfixLdapConf() {
	cat > "$1" <<EOF
# Postfix LDAP query
server_host = $LDAP_HOST
server_port = $LDAP_PORT
bind_dn = $LDAP_USER_DN
bind_pw = $LDAP_PASSWORD
bind = yes
search_base = $2
query_filter = $3
result_attribute = $4
EOF
	test $? -eq 0 &&
	chmod 640 "$1" &&
	chown root:postfix "$1"
}

setupDovecot() {
	echo "Configuring dovecot ..."
	# Generate dovecot LDAP configuration
	cat > /etc/dovecot/dovecot-ldap.conf.ext <<EOF
# Dovecot LDAP mailbox resultion query (included in /etc/dovecot.conf)
hosts = ldap:10389
dn = $LDAP_USER_DN
dnpass = $LDAP_PASSWORD
tls = no
auth_bind = yes
base = $LDAP_MAILBOX_SEARCH_BASE
user_attrs = =mail=maildir:/var/vmail/%d/%n/
user_filter = (&(objectClass=inetOrgPerson)(mail=%u))
pass_attrs = 
pass_filter = (&(objectClass=inetOrgPerson)(mail=%u))
scope = subtree
ldap_version = 3
EOF
	test $? -eq 0 &&
	chmod 600 /etc/dovecot/dovecot-ldap.conf.ext &&
	# Link ldap conf as user db
	ln -sf /etc/dovecot/dovecot-ldap.conf.ext /etc/dovecot/dovecot-ldap-userdb.conf.ext
}

setupSslCertificate &&
setupPostfix &&
setupDovecot
