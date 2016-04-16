#!/bin/sh

# Start rsyslog to collect postfix & dovecot logs and print them to stdout
rsyslogd -n -f /etc/rsyslog.conf &
SYSLOG_PID=$!

# Setup postfix+dovecot+ldap configuration
setup-mail || exit 1

startPostfix() {
	/usr/sbin/postfix -c /etc/postfix start
}

startDovecot() {
	DOVECOT_CONF=/etc/dovecot/dovecot.conf
	DOVECOT_BASEDIR=$(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //') &&
	mkdir -p "$DOVECOT_BASEDIR" && chown dovecot:dovecot "$DOVECOT_BASEDIR" && chmod 0755 "$DOVECOT_BASEDIR" &&
	/usr/sbin/dovecot -c "$DOVECOT_CONF"
}

awaitTermination() {
	if [ ! -z "$1" ]; then
		# Wait until process has been terminated
		while [ $(ps -ef | grep -Ec "^\s*$1 ") -ne 0 ]; do
			sleep 1
		done
	fi
}

terminate() {
	# Terminate
	trap : 1 2 3 15 # Disable termination call on signal to avoid infinite recursion
	POSTFIX_PID=$(cat /var/spool/postfix/pid/master.pid 2>/dev/null)
	DOVECOT_PID=$(cat $(/usr/sbin/dovecot -c $DOVECOT_CONF -a | grep '^base_dir = ' | sed 's/^base_dir = //')master.pid 2>/dev/null)
	kill $POSTFIX_PID 2>/dev/null || echo "Couldn't terminate postfix since it is not running" >&2
	kill $DOVECOT_PID 2>/dev/null || echo "Couldn't terminate dovecot since it is not running" >&2
	awaitTermination $POSTFIX_PID
	awaitTermination $DOVECOT_PID
	kill $SYSLOG_PID
	awaitTermination $SYSLOG_PID
	exit 0
}

# Register signal handler for graceful termination (SIGHUP SIGINT SIGQUIT SIGTERM)
trap terminate 1 2 3 15

if [ "$1" = 'run' ]; then
	startPostfix
	startDovecot
	wait
elif [ "$1" = 'receivers' ]; then
	grep -E 'to=<.*?>' /var/log/maillog* | grep -v 'NOQUEUE: reject:' | grep -Po '(?<=to=\<)[^>]+' | sort | uniq
else
	exec $1
fi
