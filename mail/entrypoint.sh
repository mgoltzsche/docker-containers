#!/bin/dumb-init /bin/sh

rsyslogd # Start rsyslog (required for postfix logging)
/setup/setup.sh || exit 1 # setup postfix+dovecot+ldap configuration

startConsulClient() {
	/entrypoint-consul.sh client -retry-join=consul &
#	echo $? > /var/run/consul
}

startPostfix() {
	/usr/sbin/postfix -c /etc/postfix start >/dev/null 2>&1
	tail -f /var/log/maillog &
#	echo $? > /var/run/postfix
}

#stopPostfix() {
#	kill $(/var/run/postfix)
#}

startDovecot() {
	DOVECOT_CONF=/etc/dovecot/dovecot.conf
	DOVECOT_BASEDIR=$(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')
	mkdir -p "$DOVECOT_BASEDIR" && chown dovecot:dovecot "$DOVECOT_BASEDIR" && chmod 0755 "$DOVECOT_BASEDIR" &&
	/usr/sbin/dovecot -c "$DOVECOT_CONF"
	tail -f /var/log/dovecot.info &
	tail -f /var/log/dovecot &
#	echo $? > "$DOVECOT_BASEDIR/master.pid"
}

#stopDovecot() {
#	kill $($DOVECOT_BASEDIR/master.pid)
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
