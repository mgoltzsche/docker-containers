#!/bin/sh

# Wait for logstash service to become available
if [ "$LOGSTASH_ENABLED" ]; then
	LOGSTASH_HOST=logstash
	LOGSTASH_PORT=5000
	until nc -vzw1 "$LOGSTASH_HOST" "$LOGSTASH_PORT" 2>/dev/null; do
		echo "Waiting for $LOGSTASH_HOST:$LOGSTASH_PORT"
		sleep 1
	done
fi

case "$1" in rails|thin|rake)
	# Write database.yml if missing
	if [ ! -f './config/database.yml' ]; then
		if [ "$POSTGRES_PORT_5432_TCP" ]; then
			# Configure postgres
			DB_ADAPTER='postgresql'
			DB_HOST="${POSTGRES_PORT_5432_TCP_HOST:-postgres}"
			DB_PORT="${POSTGRES_PORT_5432_TCP_PORT:-5432}"
			DB_USERNAME="${POSTGRES_ENV_POSTGRES_USER:-postgres}"
			DB_PASSWORD="${POSTGRES_ENV_POSTGRES_PASSWORD}"
			DB_DATABASE="${POSTGRES_ENV_POSTGRES_DB:-redmine}"
			DB_ENCODING=utf8
		else
			# Configure sqlite as fallback
			echo "Warning: Using sqlite since no POSTGRES_PORT_5432_TCP environment variable specified" >&2
			echo >&2
			DB_ADAPTER='sqlite3'
			DB_HOST='localhost'
			DB_USERNAME='redmine'
			DB_DATABASE='sqlite/redmine.db'
			DB_ENCODING=utf8
			mkdir -p "$(dirname "$DB_DATABASE")"
			chown -R redmine:redmine "$(dirname "$DB_DATABASE")"
		fi

		cat > './config/database.yml' <<-YML
			$RAILS_ENV:
			  adapter: $DB_ADAPTER
			  host: $DB_HOST
			  port: $DB_PORT
			  username: $DB_USERNAME
			  password: "$DB_PASSWORD"
			  database: $DB_DATABASE
			  encoding: $DB_ENCODING
		YML
	fi

	# Write configuration.yml if missing
	if [ ! -f './config/configuration.yml' ]; then
		cat > './config/configuration.yml' <<-YML
			$RAILS_ENV:
			  attachments_storage_path: /redmine/files
			  email_delivery:
			    delivery_method: :smtp
			    smtp_settings:
			      address: "${SMTP_HOST:-mail}"
			      port: ${SMTP_PORT:-25}
			      domain: "${SMTP_DOMAIN:-example.org}"
			      authentication: :plain
			      user_name: "${SMTP_USER:-redmine}"
			      password: "${SMTP_PASSWORD:-redmine}"
			      tls: ${SMTP_TLS:-false}
			      enable_starttls_auto: ${SMTP_STARTTLS:-false}
		YML
	fi

	# Ensure the right database adapter is active in Gemfile.lock
	bundle install --without development test || exit 1

	# Generate secret
	if [ ! -s config/secrets.yml ]; then
		if [ "$REDMINE_SECRET_KEY_BASE" ]; then
			cat > 'config/secrets.yml' <<-YML
				$RAILS_ENV:
				  secret_key_base: "$REDMINE_SECRET_KEY_BASE"
			YML
		elif [ ! -f config/initializers/secret_token.rb ]; then
			rake generate_secret_token || exit 2
		fi
	fi

	# Wait for DB to become available
	until ERROR=$(echo "SELECT 1;" | gosu redmine rails db -p 2>&1); do
		echo "Waiting for $DB_ADAPTER://$DB_USERNAME@$DB_HOST:$DB_PORT/$DB_DATABASE to become available: $ERROR"
		sleep 1
	done

	# Migrate DB
	if [ "$1" != 'rake' -a -z "$REDMINE_NO_DB_MIGRATE" ]; then
		echo "Migrating database. Disable this by setting REDMINE_NO_DB_MIGRATE=true" >&2
		gosu redmine rake db:migrate || exit 4
	fi

	# Insert Redmine default configuration
	if echo "SELECT COUNT(*)||'trackers' FROM trackers;" | gosu redmine rails db -p | grep -qw '0trackers' && [ -z "$REDMINE_NO_DEFAULT_DATA" ]; then
		echo "Inserting default configuration data. Disable this by setting REDMINE_NO_DEFAULT_DATA=true" >&2
		gosu redmine rake redmine:load_default_data &&
		gosu redmine rake tmp:cache:clear &&
		gosu redmine rake tmp:sessions:clear ||
		exit 5
	fi

	# Install or migrate Redmine Backlogs plugin
	if echo "SELECT COUNT(*)||'rbsettings' FROM settings WHERE name='plugin_redmine_backlogs';" | gosu redmine rails db -p | grep -qw '0rbsettings' && [ -z "$REDMINE_NO_DEFAULT_DATA" ]; then # Install
		gosu redmine rake redmine:backlogs:install \
			corruptiontest=true \
			story_trackers=Feature \
			task_tracker=Task \
			labels=false ||
		exit 6
		echo "Copying Feature workflow to Task workflow"
		WORKFLOW_SQL="SELECT (SELECT id FROM trackers WHERE name='Task'),role_id,old_status_id,new_status_id FROM workflows WHERE type='WorkflowTransition' AND tracker_id=(SELECT id FROM trackers WHERE name='Feature');"
		# Cannot use rails db --mode list since output is not supported when postgresql adapter is used
		echo "$WORKFLOW_SQL" | gosu redmine rails db -p | grep -Eo '\d+\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*\d+' | \
			sed -e 's/\|/,/g' -e 's/ //g' -e 's/$/);/' | \
			xargs -n1 echo "INSERT INTO workflows(type,assignee,author,tracker_id,role_id,old_status_id,new_status_id) VALUES('WorkflowTransition','f','f'," | \
			gosu redmine rails db -p ||
		(echo "Failed to copy 'Feature' tracker workflow to 'Task' tracker workflow. You may have to create the workflow yourself to be able to interact with a backlogs task board" >&2; exit 7)
	elif [ -z "$REDMINE_NO_DB_MIGRATE" ]; then # Migrate
		gosu redmine rake redmine:plugins:migrate || exit 8
	fi

	# Configure host name
	HOST_NAME="$(echo "SELECT 'hostname:'||value FROM settings WHERE name='host_name';" | rails db -p | grep -E 'hostname:' | sed s/hostame://)"
	if [ -z "$HOST_NAME" ]; then
		HOST_NAME="${REDMINE_HOST_NAME:-$(hostname -f)}"
		echo "Configuring Redmine host name $HOST_NAME since unconfigured instance"

		if [ -z "$HOST_NAME" ]; then
			echo "Could not configure Redmine host name." >&2
			echo "Please set REDMINE_HOST_NAME or configure a fully qualified system host name with e.g. docker's -h option." >&2
			exit 9
		fi

		echo "INSERT INTO settings(name,value) VALUES('host_name','$HOST_NAME');" | gosu redmine rails db -p
	fi

	# Configure LDAP
	if [ ! -z "$LDAP_AUTH" ]; then
		echo "Configuring LDAP auth source '$LDAP_AUTH'. Disable this by setting LDAP_AUTH=''"
		HOST_DOMAIN=$(hostname -d)
		LDAP_HOST=${LDAP_HOST:-ldap}
		LDAP_PORT=${LDAP_PORT:-389}
		LDAP_DOMAIN_CONTEXT=${LDAP_DOMAIN_CONTEXT:-"dc=${HOST_DOMAIN/./,dc=}"}
		LDAP_BASE_DN=${LDAP_BASE_DN:-$LDAP_DOMAIN_CONTEXT}
		LDAP_ACCOUNT=${LDAP_USER_DN:-"cn=redmine,ou=Special Users,$LDAP_DOMAIN_CONTEXT"}
		LDAP_ACCOUNT_PASSWORD=${LDAP_USER_PW:-Secret123}
		LDAP_FILTER=${LDAP_FILTER:-}
		LDAP_ATTR_LOGIN=${LDAP_ATTR_LOGIN:-cn}
		LDAP_ATTR_FIRSTNAME=${LDAP_ATTR_FIRSTNAME:-givenName}
		LDAP_ATTR_LASTNAME=${LDAP_ATTR_LASTNAME:-sn}
		LDAP_ATTR_MAIL=${LDAP_ATTR_MAIL:-mail}
		LDAP_ONTHEFLY_REGISTER=${LDAP_ONTHEFLY_REGISTER:-t}
		LDAP_TLS=${LDAP_TLS:-f}
		LDAP_TIMEOUT=${LDAP_TIMEOUT:-30}
		set | grep -E '^LDAP_' | sed -E 's/(^[^=]+_(PASSWORD|PW)=).*/\1***/i' # Show variables

		if ! echo "SELECT 'auth:'||name FROM auth_sources WHERE name='$LDAP_AUTH';" | rails db -p | grep -qw "auth:$LDAP_AUTH"; then
			# Insert auth source if unconfigured
			echo "INSERT INTO auth_sources(type,name,host,port,account,account_password,base_dn,filter,attr_login,attr_mail,attr_firstname,attr_lastname,onthefly_register,tls,timeout)
					VALUES('AuthSourceLdap','$LDAP_AUTH','$LDAP_HOST',$LDAP_PORT,
						'$LDAP_ACCOUNT','$LDAP_ACCOUNT_PASSWORD','$LDAP_BASE_DN',
						'$LDAP_FILTER','$LDAP_ATTR_LOGIN','$LDAP_ATTR_MAIL',
						'$LDAP_ATTR_FIRSTNAME','$LDAP_ATTR_LASTNAME',
						'$LDAP_ONTHEFLY_REGISTER','$LDAP_TLS',$LDAP_TIMEOUT);" | gosu redmine rails db -p ||
				(echo "Failed to insert LDAP auth source $LDAP_AUTH"; exit 10)
		else
			# Update existing auth source
			echo "UPDATE auth_sources SET type='AuthSourceLdap',
					host='$LDAP_HOST',port=$LDAP_PORT,
					account='$LDAP_ACCOUNT',
					account_password='$LDAP_ACCOUNT_PASSWORD',
					base_dn='$LDAP_BASE_DN',
					filter='$LDAP_FILTER',
					attr_login='$LDAP_ATTR_LOGIN',
					attr_mail='$LDAP_ATTR_MAIL',
					attr_firstname='$LDAP_ATTR_FIRSTNAME',
					attr_lastname='$LDAP_ATTR_LASTNAME',
					onthefly_register='$LDAP_ONTHEFLY_REGISTER',
					tls='$LDAP_TLS',timeout=$LDAP_TIMEOUT
					WHERE name='$LDAP_AUTH';" | gosu redmine rails db -p ||
				(echo "Failed to update LDAP auth source $LDAP_AUTH_NAME"; exit 11)
		fi

		LDAP_CHECK="
require 'rubygems'
require 'net/ldap'
ldap = Net::LDAP.new
ldap.host = '$LDAP_HOST'
ldap.port = $LDAP_PORT
ldap.auth '$LDAP_ACCOUNT', '$LDAP_ACCOUNT_PASSWORD'
ldap.bind
ldap.search( :base => '$LDAP_ACCOUNT' ) do |entry|
  exit 0
end
exit 1
"
		until echo "$LDAP_CHECK" | ruby; do
			echo "Waiting for available LDAP server $LDAP_HOST:$LDAP_PORT and user $LDAP_ACCOUNT" >&2
			sleep 1
		done
	fi

	chown -R redmine:redmine files log public/plugin_assets
	rm -f tmp/pids/server.pid

	set -- gosu redmine "$@"
	;;
esac

exec "$@"
