#!/bin/sh

set -e
	: ${RC_LANGUAGE:=en_US}
	: ${RC_DEFAULT_HOST:=ssl://mail}
	: ${RC_DEFAULT_PORT:=993}
	: ${RC_SMTP_SERVER:=mail}
	: ${RC_SMTP_USER:=%u}
	: ${RC_SMTP_PASS:=%p}
	: ${RC_AUTO_CREATE_USER:=true}
	: ${RC_IDENTITIES_LEVEL:=0}
	: ${RC_USERNAME_DOMAIN:=}
	: ${RC_SUPPORT_URL:=}
	: ${RC_ENABLE_SPELLCHECK:=false}
	: ${RC_ENABLE_INSTALLER:=true}
	: ${RC_DES_KEY:=$(date +%s | sha256sum | base64 | head -c 24)}
	: ${DB_TYPE:=sqlite}
	: ${DB_HOST:=postgres}
	: ${DB_DATABASE:=}
	: ${DB_USERNAME:=roundcube}
	: ${DB_PASSWORD:=}

case "$DB_TYPE" in
	sqlite)
		[ "$DB_DATABASE" ] || DB_DATABASE=/roundcube/sqlite.db
		RC_DB_DSNW="sqlite:///$DB_DATABASE?mode=0646"
	;;
	pgsql)
		[ "$DB_DATABASE" ] || DB_DATABASE=$DB_USERNAME
		RC_DB_DSNW="pgsql://$DB_USER:$DB_PASSWORD@$DB_HOST/$DB_DATABASE"
	;;
	*)
		echo "Unsupported DB type: $DB_TYPE" >&2
		exit 1
	;;
esac

echo 'Setting up roundcube with (see https://github.com/roundcube/roundcubemail/wiki/Configuration):'
set | grep -E '^DB_|^RC_' | sed -E 's/(^[^=]+_(PASSWORD|DSNW|KEY)=).+/\1***/i' | xargs -n1 echo ' ' # Show variables

CFG_CONTENT=

for CFG_KEY_UPPER in $(set | grep -Eo '^RC_[^=]+' | sed 's/^RC_//'); do
	CFG_KEY=$(echo -n "$CFG_KEY_UPPER" | tr '[:upper:]' '[:lower:]') # User name lower case
	CFG_VAL=$(eval "echo \$RC_$CFG_KEY_UPPER")
	echo "$CFG_KEY" | grep -Eq '^enable|^auto|level$|port$' || CFG_VAL="'$CFG_VAL'"
	CFG_CONTENT="$(echo "$CFG_CONTENT"; echo "\$config['$CFG_KEY'] = $CFG_VAL;")"
done

cat > /roundcube/config/config.inc.php <<-EOF
	<?php
	\$config['plugins'] = array();
	$CFG_CONTENT
	?>
EOF
