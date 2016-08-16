#!/bin/sh

SYSLOG_ENABLED=${SYSLOG_ENABLED:=false}
SYSLOG_HOST=${SYSLOG_HOST:=syslog}
SYSLOG_PORT=${SYSLOG_PORT:=514}
LDAP_ENABLED=${LDAP_ENABLED:=false}
LDAP_HOST=${LDAP_HOST:=ldap}
LDAP_PORT=${LDAP_PORT:=389}
LDAP_SUFFIX=${LDAP_SUFFIX:='dc='$(hostname -d | sed s/\\./,dc=/g)}
LDAP_BIND_DN="${LDAP_BIND_DN:=cn=nginx,ou=System Users,$LDAP_SUFFIX}"
LDAP_BIND_PW="${LDAP_BIND_PW:=nginxSecret123}"
LDAP_GROUP_ATTR=${LDAP_GROUP_ATTR:=uniquemember}
LDAP_GROUP_ATTR_IS_DN=${LDAP_GROUP_ATTR_IS_DN:=on}

[ ! "$LDAP_ENABLED" = 'true' ] || [ ! "$LDAP_SUFFIX" = 'dc=' ] || (echo 'LDAP_SUFFIX not defined' >&2; false) || exit 1

setupNginx() {
	echo -n "Remote syslog support: "
	if [ "$SYSLOG_ENABLED" = true ]; then
		echo "enabled"
		awaitSuccess "Waiting for syslog UDP server $SYSLOG_HOST:$SYSLOG_PORT" nc -uzvw1 "$SYSLOG_HOST" "$SYSLOG_PORT"
		cat > /etc/nginx/conf.d/logging.conf <<-EOF
			error_log syslog:server=$SYSLOG_HOST:$SYSLOG_PORT;
			access_log syslog:server=$SYSLOG_HOST:$SYSLOG_PORT,facility=local7,tag=nginx,severity=info access;
		EOF
	else
		echo "disabled"
		cat > /etc/nginx/conf.d/logging.conf <<-EOF
			error_log stderr;
			access_log off;
		EOF
	fi
	echo -n "LDAP support:          "
	if [ "$LDAP_ENABLED" = true ]; then
		echo "enabled"
		awaitSuccess "Waiting for LDAP server $LDAP_HOST:$LDAP_PORT" nc -zvw1 "$LDAP_HOST" "$LDAP_PORT"
		cat > /etc/nginx/conf.d/ldap.conf <<-EOF
			ldap_server ldap_master {
				url ldap://$LDAP_HOST:$LDAP_PORT/$LDAP_SUFFIX?cn?sub?(objectClass=person);
				binddn "$LDAP_BIND_DN";
				binddn_passwd "$LDAP_BIND_PW";
				group_attribute $LDAP_GROUP_ATTR;
				group_attribute_is_dn $LDAP_GROUP_ATTR_IS_DN;
				require valid_user;
			}
		EOF
	else
		echo "disabled"
		echo > /etc/nginx/conf.d/ldap.conf
	fi
}

# Provides the nginx PID
nginxPid() {
	cat /var/run/nginx.pid 2>/dev/null
	return 0
}

# Runs the provided command until it succeeds.
# Takes the error message to be displayed if it doesn't succeed as first argument.
awaitSuccess() {
	MSG="$1"
	shift
	until $@ >/dev/null 2>/dev/null; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 1
	done
}

# Terminates the provided PID and waits until it is terminated
terminatePid() {
	kill $1 2>/dev/null
	awaitSuccess '' isProcessTerminated $1
}

# Tests if the provided PID is terminated
isProcessTerminated() {
	! ps -o pid | grep -wq ${1:-0}
}

# Terminates the whole container orderly
terminateGracefully() {
	trap : SIGHUP SIGINT SIGQUIT SIGTERM # Unregister signal handler to avoid infinite recursion
	terminatePid ${nginxPid}
	exit 0
}

case "$1" in
	nginx)
		(NGINX_PID=$(nginxPid) && [ ! "$NGINX_PID" ] || isProcessTerminated $NGINX_PID || (echo 'nginx is already running' >&2; false)) &&
		trap terminateGracefully SIGHUP SIGINT SIGQUIT SIGTERM &&
		rm -f /var/run/nginx.pid &&
		setupNginx &&
		nginx -tq || exit $?
		$@ &
		wait
	;;
	*)
		$@
		exit $?
	;;
esac
