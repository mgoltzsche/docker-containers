#!/bin/sh

set -e
	: ${RC_LANGUAGE:=en_US}
	: ${RC_LOG_DRIVER:=syslog}
	: ${RC_SYSLOG_ID:=roundcube}
	: ${RC_DEBUG_LEVEL:=1} # sum of: 1 = show in log; 4 = show in browser
	: ${RC_DEFAULT_HOST:=mail} # Use ssl:// prefix to encrypt. Then CA certificate for remote host should be placed in /etc/ssl/
	: ${RC_DEFAULT_PORT:=143}
	: ${RC_SMTP_SERVER:=mail} # Use tls:// prefix to encrypt
	: ${RC_SMTP_PORT:=25}
	: ${RC_SMTP_USER:=%u}
	: ${RC_SMTP_PASS:=%p}
	: ${RC_SMTP_HELO_HOST:=$(hostname -f)}
	: ${RC_SMTP_LOG:=false}
	: ${RC_AUTO_CREATE_USER:=true}
	: ${RC_CREATE_DEFAULT_FOLDERS:=true}
	: ${RC_USERNAME_DOMAIN:=}
	: ${RC_PASSWORD_CHARSET:=UTF-8}
	: ${RC_IDENTITIES_LEVEL:=1}
	: ${RC_SUPPORT_URL:=}
	: ${RC_ENABLE_SPELLCHECK:=false}
	: ${RC_ENABLE_INSTALLER:=true} # Set to true serves /installer
	: ${RC_DES_KEY:=$(date +%s | sha256sum | base64 | head -c 24)}
	: ${RC_DB_PREFIX:=rc_}
	: ${DB_TYPE:=sqlite}
	: ${DB_HOST:=postgres}
	: ${DB_DATABASE:=}
	: ${DB_USERNAME:=roundcube}
	: ${DB_PASSWORD:=}

case "$DB_TYPE" in
	sqlite)
		[ "$DB_DATABASE" ] || DB_DATABASE=/db/roundcube-sqlite.db
		RC_DB_DSNW="sqlite:///$DB_DATABASE?mode=0646"
		echo "WARN: Running roundcube with sqlite DB $DB_DATABASE" >&2
	;;
	pgsql)
		[ "$DB_DATABASE" ] || DB_DATABASE=$DB_USERNAME
		RC_DB_DSNW="pgsql://$DB_USERNAME:$DB_PASSWORD@$DB_HOST/$DB_DATABASE"
	;;
	*)
		echo "Unsupported DB type: $DB_TYPE" >&2
		exit 1
	;;
esac

# Runs the provided command until it succeeds.
# Takes the error message to be displayed if it doesn't succeed as first argument.
awaitSuccess() {
	MSG="$1"
	shift
	until $@; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 1
	done
}

writeConfig() {
	echo 'Setting up roundcube with (see https://github.com/roundcube/roundcubemail/wiki/Configuration):'
	set | grep -E '^DB_|^RC_' | sed -E 's/(^[^=]+_(PASSWORD|DSNW|KEY)=).+/\1***/i' | xargs -n1 echo ' ' # Show variables

	CFG_CONTENT=

	for CFG_KEY_UPPER in $(set | grep -Eo '^RC_[^=]+' | sed 's/^RC_//'); do
		CFG_KEY=$(echo -n "$CFG_KEY_UPPER" | tr '[:upper:]' '[:lower:]') # User name lower case
		CFG_VAL=$(eval "echo \$RC_$CFG_KEY_UPPER")
		echo "$CFG_KEY" | grep -Eq '^enable|^auto|level$|port$|_log$' || CFG_VAL="'$CFG_VAL'"
		CFG_CONTENT="$(echo "$CFG_CONTENT"; echo "\$config['$CFG_KEY'] = $CFG_VAL;")"
	done

	cat > /roundcube/config/config.inc.php <<-EOF
		<?php
		$CFG_CONTENT
		\$config['plugins'] = array();
	EOF
}

setupInstallerIfEnabled() {
	if [ "$RC_ENABLE_INSTALLER" = 'true' ]; then
		cp -r /roundcube-installer /roundcube/installer &&
		chown -R root:www-data /roundcube/installer
	else
		rm -rf /roundcube/installer
	fi
}

testConfig() {
	gosu www-data hhvm -c /etc/hhvm/server.ini /rcinit.php testconfig
}

waitForDB() {
	if [ "$DB_TYPE" = "pgsql" ]; then
		export PDO_DB_DSN="pgsql:host=$DB_HOST;port=5432;dbname=$DB_DATABASE"
		export PDO_DB_USERNAME="$DB_USERNAME"
		export PDO_DB_PASSWORD="$DB_PASSWORD"
		awaitSuccess "Waiting for postgres DB server $DB_HOST:5432" gosu www-data hhvm -c /etc/hhvm/server.ini /rcinit.php testconnection
		unset PDO_DB_DSN PDO_DB_USERNAME PDO_DB_PASSWORD
	fi
}

initDBIfEmpty() {
	if ! gosu www-data hhvm -c /etc/hhvm/server.ini /rcinit.php testschema; then
		gosu www-data hhvm -c /etc/hhvm/server.ini /rcinit.php initschema
	fi
}

waitForMailServer() {
	if [ ! "$SKIP_MAIL_SERVER_CHECK" ]; then
		awaitSuccess "Waiting for MDA on $RC_DEFAULT_HOST:$RC_DEFAULT_PORT" nc -zvw1 "$RC_DEFAULT_HOST" "$RC_DEFAULT_PORT" &&
		awaitSuccess "Waiting for MTA on $RC_SMTP_SERVER:$RC_SMTP_PORT" nc -zvw1 "$RC_SMTP_SERVER" "$RC_SMTP_PORT"
	fi
}

writeConfig &&
testConfig &&
setupInstallerIfEnabled &&
waitForDB &&
initDBIfEmpty &&
waitForMailServer

