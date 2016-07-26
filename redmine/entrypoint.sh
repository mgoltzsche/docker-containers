#!/bin/sh

export LOG_LEVEL=${LOG_LEVEL:-ERROR}
export SYSLOG_REMOTE_ENABLED=${SYSLOG_REMOTE_ENABLED:-false}
export SYSLOG_HOST=${SYSLOG_HOST:-syslog}
export SYSLOG_PORT=${SYSLOG_PORT:-514}
HOST_DOMAIN=$(hostname -d)
LDAP_AUTH=${LDAP_AUTH:-} # Set auth name to enable ldap
LDAP_HOST=${LDAP_HOST:-ldap}
LDAP_PORT=${LDAP_PORT:-389}
LDAP_DOMAIN_CONTEXT=${LDAP_DOMAIN_CONTEXT:-"dc=${HOST_DOMAIN/./,dc=}"}
LDAP_BASE_DN=${LDAP_BASE_DN:-$LDAP_DOMAIN_CONTEXT}
LDAP_USER_DN=${LDAP_USER_DN:-"cn=redmine,ou=Special Users,$LDAP_DOMAIN_CONTEXT"}
LDAP_USER_PW=${LDAP_USER_PW:-Secret123}
LDAP_FILTER=${LDAP_FILTER:-}
LDAP_ATTR_LOGIN=${LDAP_ATTR_LOGIN:-cn}
LDAP_ATTR_FIRSTNAME=${LDAP_ATTR_FIRSTNAME:-givenName}
LDAP_ATTR_LASTNAME=${LDAP_ATTR_LASTNAME:-sn}
LDAP_ATTR_MAIL=${LDAP_ATTR_MAIL:-mail}
LDAP_ONTHEFLY_REGISTER=${LDAP_ONTHEFLY_REGISTER:-t}
LDAP_TLS=${LDAP_TLS:-f}
LDAP_TIMEOUT=${LDAP_TIMEOUT:-30}
SMTP_ENABLED=${SMTP_ENABLED:-false}
SMTP_HOST=${SMTP_HOST:-mail}
SMTP_PORT=${SMTP_PORT:-25}
SMTP_DOMAIN=${SMTP_DOMAIN:-$HOST_DOMAIN}
SMTP_USER=${SMTP_USER:-$(echo "$LDAP_USER_DN" | cut -d , -f 1 | cut -d = -f 2)}
SMTP_PASSWORD=${SMTP_PASSWORD:-"$LDAP_USER_PW"}
SMTP_TLS=${SMTP_TLS:-false}
SMTP_STARTTLS=${SMTP_STARTTLS:-false}
SMTP_DOMAIN=$(hostname -d)
DB_ADAPTER=${DB_ADAPTER:-sqlite3}
DB_ENCODING=${DB_ENCODING:-utf8}

case "$DB_ADAPTER" in
	postgresql)
		DB_HOST=${DB_HOST:-postgres}
		DB_PORT=${DB_PORT:-5432}
		DB_USERNAME=${DB_USERNAME:-postgres}
		DB_PASSWORD="$DB_PASSWORD"
		DB_DATABASE=${DB_DATABASE:-redmine}
		;;
	sqlite3)
		DB_HOST=${DB_HOST:-localhost}
		DB_USERNAME=${DB_USERNAME:-redmine}
		DB_DATABASE=${DB_DATABASE:-sqlite/redmine.db}
		mkdir -p "$(dirname "$DB_DATABASE")" || exit 1
		chown -R redmine:redmine "$(dirname "$DB_DATABASE")" || exit 1
		;;
	*)
		echo "Unsupported database adapter: '$DB_ADAPTER'" >&2
		exit 1
		;;
esac

backup() {
	# TODO: fix
	#DB_HOST=postgres; DB_PORT=5432; DB_USERNAME=redmine; gosu redmine pg_dump -h $DB_HOST -p $DB_PORT -U $DB_USERNAME -w --inserts --blobs --no-tablespaces --no-owner --no-privileges --disable-triggers --disable-dollar-quoting --serializable-deferrable
	pg_dump -h $DB_HOST -p $DB_PORT -U $DB_USERNAME -w --inserts --blobs --no-tablespaces --no-owner --no-privileges --disable-triggers --disable-dollar-quoting --serializable-deferrable
}

restore() {
	# TODO: psql call + database drop/create
	false
}

waitForTcpService() {
	until nc -zvw1 "$1" "$2" 2>/dev/null; do
		echo "Waiting for TCP service $1:$2" >&2
		sleep 3
	done
}

waitForUdpService() {
	until nc -uzvw1 "$1" "$2" 2>/dev/null; do
		echo "Waiting for UDP service $1:$2" >&2
		sleep 3
	done
}

case "$1" in rails|thin|rake)
	echo 'Setting up redmine with:'
	set | grep -E '^DB_|^LOG_LEVEL=|^SYSLOG_|^LDAP_|^SMTP_' | sed -E 's/(^[^=]+_(PASSWORD|PW)=).+/\1***/i' | xargs -n1 echo ' ' # Show variables
	[ ! "$DB_ADAPTER" = 'sqlite3' ] || echo 'Warning: Using sqlite3 as redmine database' >&2

	# Write db config
	cat > ./config/database.yml <<-YML
		$RAILS_ENV:
		  adapter: "$DB_ADAPTER"
		  host: "$DB_HOST"
		  port: $DB_PORT
		  username: "$DB_USERNAME"
		  password: "$DB_PASSWORD"
		  database: "$DB_DATABASE"
		  encoding: "$DB_ENCODING"
	YML

	gosu redmine echo > /redmine/.pgpass "$DB_HOST:$DB_PORT:$DB_DATABASE:$DB_USERNAME:$DB_PASSWORD" &&
	chmod 0600 /redmine/.pgpass || exit 1

	# Write mail config
	if [ "$SMTP_ENABLED" = 'true' ]; then
		cat > ./config/configuration.yml <<-YML
			$RAILS_ENV:
			  attachments_storage_path: /redmine/files
			  email_delivery:
				delivery_method: :smtp
				smtp_settings:
				  address: "$SMTP_HOST"
				  port: $SMTP_PORT
				  domain: "$SMTP_DOMAIN"
				  authentication: :plain
				  user_name: "$SMTP_USER"
				  password: "$SMTP_PASSWORD"
				  tls: $SMTP_TLS
				  enable_starttls_auto: $SMTP_STARTTLS
		YML
	fi

	# Write log config
	cat > ./config/additional_environment.rb <<-YML
		if ENV['SYSLOG_REMOTE_ENABLED'] == 'true'
		  config.logger = RemoteSyslogLogger.new(ENV['SYSLOG_HOST'], ENV['SYSLOG_PORT'], :program => 'redmine')
		else
		  config.logger = Logger.new(STDOUT)
		end

		config.logger.level = Logger::$LOG_LEVEL
	YML

	# Wait for syslog server
	[ ! "$SYSLOG_REMOTE_ENABLED" = 'true' ] || waitForUdpService "$SYSLOG_HOST" "$SYSLOG_PORT"

	# Ensure the right database adapter is active in Gemfile.lock
	bundle install --without development test || exit 1

	# Generate secret
	if [ ! -s config/secrets.yml ]; then
		if [ "$REDMINE_SECRET_KEY_BASE" ]; then
			cat > config/secrets.yml <<-YML
				$RAILS_ENV:
				  secret_key_base: "$REDMINE_SECRET_KEY_BASE"
			YML
		elif [ ! -f config/initializers/secret_token.rb ]; then
			rake generate_secret_token || exit 2
		fi
	fi

	# Wait for DB to become available
	until ERROR=$(echo "SELECT 1;" | gosu redmine rails db -p 2>&1); do
		echo "Waiting for database $DB_ADAPTER://$DB_USERNAME@$DB_HOST:$DB_PORT/$DB_DATABASE: $ERROR"
		ERROR=
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
			gosu redmine rails db -p 1>/dev/null ||
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

		echo "INSERT INTO settings(name,value) VALUES('host_name','$HOST_NAME');" | gosu redmine rails db -p 1>/dev/null
	fi

	# Configure LDAP
	if [ "$LDAP_AUTH" ]; then
		echo "Configuring LDAP auth source '$LDAP_AUTH'. Disable this by setting LDAP_AUTH=''"

		if ! echo "SELECT 'auth:'||name FROM auth_sources WHERE name='$LDAP_AUTH';" | rails db -p | grep -qw "auth:$LDAP_AUTH"; then
			# Insert auth source if unconfigured
			echo "INSERT INTO auth_sources(type,name,host,port,account,account_password,base_dn,filter,attr_login,attr_mail,attr_firstname,attr_lastname,onthefly_register,tls,timeout)
					VALUES('AuthSourceLdap','$LDAP_AUTH','$LDAP_HOST',$LDAP_PORT,
						'$LDAP_USER_DN','$LDAP_USER_PW','$LDAP_BASE_DN',
						'$LDAP_FILTER','$LDAP_ATTR_LOGIN','$LDAP_ATTR_MAIL',
						'$LDAP_ATTR_FIRSTNAME','$LDAP_ATTR_LASTNAME',
						'$LDAP_ONTHEFLY_REGISTER','$LDAP_TLS',$LDAP_TIMEOUT);" | gosu redmine rails db -p 1>/dev/null ||
				(echo "Failed to insert LDAP auth source $LDAP_AUTH"; exit 10)
		else
			# Update existing auth source
			echo "UPDATE auth_sources SET type='AuthSourceLdap',
					host='$LDAP_HOST',port=$LDAP_PORT,
					account='$LDAP_USER_DN',
					account_password='$LDAP_USER_PW',
					base_dn='$LDAP_BASE_DN',
					filter='$LDAP_FILTER',
					attr_login='$LDAP_ATTR_LOGIN',
					attr_mail='$LDAP_ATTR_MAIL',
					attr_firstname='$LDAP_ATTR_FIRSTNAME',
					attr_lastname='$LDAP_ATTR_LASTNAME',
					onthefly_register='$LDAP_ONTHEFLY_REGISTER',
					tls='$LDAP_TLS',timeout=$LDAP_TIMEOUT
					WHERE name='$LDAP_AUTH';" | gosu redmine rails db -p 1>/dev/null ||
				(echo "Failed to update LDAP auth source $LDAP_AUTH_NAME"; exit 11)
		fi

		LDAP_CHECK="$(cat <<-EOF
			require 'rubygems'
			require 'net/ldap'
			ldap = Net::LDAP.new
			ldap.host = '$LDAP_HOST'
			ldap.port = $LDAP_PORT
			ldap.auth '$LDAP_USER_DN', '$LDAP_USER_PW'
			ldap.bind
			ldap.search( :base => '$LDAP_USER_DN' ) do |entry|
			  print 'found'
			  exit 0
			end
			exit 1
		EOF
		)"
		until echo "$LDAP_CHECK" | ruby; do
			echo "Waiting for available LDAP server $LDAP_HOST:$LDAP_PORT and user $LDAP_USER_DN" >&2
			sleep 1
		done
	fi

	chown -R redmine:redmine files log public/plugin_assets
	rm -f tmp/pids/server.pid

	if [ "$SMTP_ENABLED" = 'true' ]; then
		# Wait for mail server
		waitForTcpService "$SMTP_HOST" "$SMTP_PORT"
	fi

	set -- gosu redmine "$@"
	;;
esac

exec "$@"
