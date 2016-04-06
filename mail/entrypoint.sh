#!/bin/dumb-init /bin/sh

# Start rsyslog to collect postfix & dovecot logs and print them to stdout
rsyslogd -n -f /etc/rsyslog.conf &

# Setup consul dns resolution
setup-consul-dns
# Setup postfix+dovecot+ldap configuration
setup-mail || exit 1

startConsulClient() {
	/entrypoint-consul.sh client -retry-join=consul &
#	echo $? > /var/run/consul
}

startPostfix() {
	/usr/sbin/postfix -c /etc/postfix start >/dev/null 2>&1
#	echo $? > /var/run/postfix
}

#stopPostfix() {
#	kill $(cat /var/spool/postfix/pid/master.pid)
#}

startDovecot() {
	DOVECOT_CONF=/etc/dovecot/dovecot.conf
	DOVECOT_BASEDIR=$(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')
	mkdir -p "$DOVECOT_BASEDIR" && chown dovecot:dovecot "$DOVECOT_BASEDIR" && chmod 0755 "$DOVECOT_BASEDIR" &&
	/usr/sbin/dovecot -c "$DOVECOT_CONF"
#	tail -f /var/log/dovecot.info &
#	tail -f /var/log/dovecot &
}

#stopDovecot() {
#	kill $($(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')/master.pid)
#}

if [ "$1" = 'run' ]; then
	startConsulClient
	startPostfix
	startDovecot
	wait

elif [ "$1" = 'receivers' ]; then
	grep -E 'to=<.*?>' /var/log/maillog* | grep -v 'NOQUEUE: reject:' | grep -Po '(?<=to=\<)[^>]+' | sort | uniq
else
	exec $1
fi
