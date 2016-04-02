#!/bin/sh

DOMAIN=$(hostname -d)

if [ -z "$DOMAIN" ]; then
	echo 'hostname -d is undefined.' >&2
	echo 'Setup a proper hostname by adding an entry to /etc/hosts like this:' >&2
	echo ' 172.17.0.2      mail.algorythm.de mail' >&2
	exit 1
fi

if [ ! -f "/etc/ssl/private/server.key" ]; then
	SUBJ="/C=DE/ST=Berlin/L=Berlin/O=algorythm/CN=$DOMAIN"
	echo "Generating new mail server certificate for '$SUBJ' ..."
	openssl req -new -newkey rsa:4096 -days 2000 -nodes -x509 -subj "$SUBJ" -keyout /etc/ssl/private/server.key -out /etc/ssl/certs/server.crt &&
	chmod 600 /etc/ssl/private/server.key
fi

cd "$(dirname $0)" &&
echo "Configuring postfix ..." &&
./setup-postfix.sh &&
echo "Configuring dovecot ..." &&
./setup-dovecot.sh
