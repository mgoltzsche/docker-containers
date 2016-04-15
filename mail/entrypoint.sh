#!/bin/sh

# Start rsyslog to collect postfix & dovecot logs and print them to stdout
rsyslogd -n -f /etc/rsyslog.conf &
SYSLOG_PID=$?

# Setup postfix+dovecot+ldap configuration
setup-mail || exit 1

startConsulClient() {
	/entrypoint-consul.sh client -retry-join=consul &
#	echo $? > /var/run/consul
}

startPostfix() {
	/usr/sbin/postfix -c /etc/postfix start
}

#stopPostfix() {
#	kill $(cat /var/spool/postfix/pid/master.pid)
#}

startDovecot() {
	DOVECOT_CONF=/etc/dovecot/dovecot.conf
	DOVECOT_BASEDIR=$(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //') &&
	mkdir -p "$DOVECOT_BASEDIR" && chown dovecot:dovecot "$DOVECOT_BASEDIR" && chmod 0755 "$DOVECOT_BASEDIR" &&
	/usr/sbin/dovecot -c "$DOVECOT_CONF"
}

#stopDovecot() {
#	kill $($(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')/master.pid)
#}

postfixPid() {
	cat /var/spool/postfix/pid/master.pid
}

dovecotPid() {
	echo $(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')/master.pid
}

awaitTermination() {
	while [ $(ps -ef | grep -Ec "^\s*$1 ") -ne 0 ]; do
		sleep 1
	done
}

terminate() {
	echo 'Terminating ...'
	kill $(postfixPid) || echo "Couldn't terminate postfix since it is not running" >&2
	kill $(dovecotPid) || echo "Couldn't terminate dovecot since it is not running" >&2
	awaitTermination $(postfixPid)
	awaitTermination $(dovecotPid)
	kill $SYSLOG_PID
}

# TODO: FIX. DOESN'T WORK
trap terminate USR1 USR2 TERM QUIT # Register termination signal handler

if [ "$1" = 'run' ]; then
	startPostfix
	startDovecot
	wait
	echo "Terminated"
elif [ "$1" = 'receivers' ]; then
	grep -E 'to=<.*?>' /var/log/maillog* | grep -v 'NOQUEUE: reject:' | grep -Po '(?<=to=\<)[^>]+' | sort | uniq
else
	exec $1
fi
