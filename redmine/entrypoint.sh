#!/bin/sh

export LOG_LEVEL=${LOG_LEVEL:-ERROR}
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
DB_BACKUP_PORT=${DB_BACKUP_PORT:-5433}
INSTALL_BACKUP_FILE="$INSTALL_BACKUP_FILE"
INSTALL_MIGRATE=${INSTALL_MIGRATE:-true}
INSTALL_DEFAULT_DATA=${INSTALL_DEFAULT_DATA:-$(if [ "$INSTALL_BACKUP_FILE" ]; then echo false; else echo true; fi)}

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

setupRedmine() {
	echo 'Setting up redmine with:'
	set | grep -E '^DB_|^LOG_LEVEL=|^LDAP_|^SMTP_|^INSTALL_' | sed -E 's/(^[^=]+_(PASSWORD|PW)=).+/\1***/i' | xargs -n1 echo ' ' # Show variables
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

	# Ensure the right database adapter is active in Gemfile.lock
	bundle install --without development test || return 1

	# Generate secret
	if [ ! -s config/secrets.yml ]; then
		if [ "$REDMINE_SECRET_KEY_BASE" ]; then
			cat > config/secrets.yml <<-YML
				$RAILS_ENV:
				  secret_key_base: "$REDMINE_SECRET_KEY_BASE"
			YML
		elif [ ! -f config/initializers/secret_token.rb ]; then
			rake generate_secret_token || return 1
		fi
	fi

	# Wait until DB is available
	waitForDB

	# Restore backup if instance is not initialized
	if [ "$INSTALL_BACKUP_FILE" ]; then
		if ! echo "SELECT 'tablesinstalled' FROM trackers;" | gosu redmine rails db -p | grep -qw tablesinstalled; then
			([ -f "$INSTALL_BACKUP_FILE" ] || (echo "Backup file $INSTALL_BACKUP_FILE not found" >&2; false)) &&
			echo "Initializing empty installation from backup INSTALL_BACKUP_FILE=$INSTALL_BACKUP_FILE" &&
			restore "$INSTALL_BACKUP_FILE" || return 1
		else
			echo "Not restoring backup $INSTALL_BACKUP_FILE since DB already initialized" >&2
			INSTALL_BACKUP_FILE=
		fi
	fi

	# Migrate database if not already done by backup restore script
	[ "$INSTALL_BACKUP_FILE" ] || migrateRedmine || return 1

	# Wait for mail server to start
	[ ! "$SMTP_ENABLED" = 'true' ] ||
		awaitSuccess "Waiting for TCP service $SMTP_HOST:$SMTP_PORT" nc -zvw1 "$SMTP_HOST" "$SMTP_PORT"
}

migrateRedmine() {
	# Migrate DB and clear cache and sessions
	if [ "$1" != 'rake' -a "$INSTALL_MIGRATE" = 'true' ]; then
		echo "Migrating database. Disable this by setting INSTALL_MIGRATE=false" >&2
		gosu redmine rake db:migrate &&
		gosu redmine rake tmp:cache:clear &&
		gosu redmine rake tmp:sessions:clear || return 1
	fi

	# Insert Redmine default configuration
	if echo "SELECT COUNT(*)||'trackers' FROM trackers;" | gosu redmine rails db -p | grep -qw '0trackers' && [ "$INSTALL_DEFAULT_DATA" = 'true' ]; then
		echo "Inserting default configuration data. Disable this by setting INSTALL_DEFAULT_DATA=false" >&2
		gosu redmine rake redmine:load_default_data ||
		return 1
	fi

	# Install or migrate Redmine Backlogs plugin
	if echo "SELECT COUNT(*)||'rbsettings' FROM settings WHERE name='plugin_redmine_backlogs';" | gosu redmine rails db -p | grep -qw '0rbsettings' && [ "$INSTALL_DEFAULT_DATA" = 'true' ]; then # Install
		gosu redmine rake redmine:backlogs:install \
			corruptiontest=true \
			story_trackers=Feature \
			task_tracker=Task \
			labels=false ||
		return 1
		echo "Copying Feature workflow to Task workflow"
		WORKFLOW_SQL="SELECT (SELECT id FROM trackers WHERE name='Task'),role_id,old_status_id,new_status_id FROM workflows WHERE type='WorkflowTransition' AND tracker_id=(SELECT id FROM trackers WHERE name='Feature');"
		# Cannot use rails db --mode list since output is not supported when postgresql adapter is used
		echo "$WORKFLOW_SQL" | gosu redmine rails db -p | grep -Eo '\d+\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*\d+' | \
			sed -e 's/\|/,/g' -e 's/ //g' -e 's/$/);/' | \
			xargs -n1 echo "INSERT INTO workflows(type,assignee,author,tracker_id,role_id,old_status_id,new_status_id) VALUES('WorkflowTransition','f','f'," | \
			gosu redmine rails db -p 1>/dev/null ||
		(echo "Failed to copy 'Feature' tracker workflow to 'Task' tracker workflow. You may have to create the workflow yourself to be able to interact with a backlogs task board" >&2; exit 7)
	elif [ "$INSTALL_MIGRATE" = 'true' ]; then # Migrate
		gosu redmine rake redmine:plugins:migrate || return 1
	fi

	# Configure host name
	HOST_NAME="$(echo "SELECT 'hostname:'||value FROM settings WHERE name='host_name';" | rails db -p | grep -E 'hostname:' | sed s/hostame://)"
	if [ -z "$HOST_NAME" ]; then
		HOST_NAME="${REDMINE_HOST_NAME:-$(hostname -f)}"
		echo "Configuring Redmine host name $HOST_NAME since unconfigured instance"

		if [ -z "$HOST_NAME" ]; then
			echo "Could not configure Redmine host name." >&2
			echo "Please set REDMINE_HOST_NAME or configure a fully qualified system host name with e.g. docker's -h option." >&2
			return 1
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
				(echo "Failed to insert LDAP auth source $LDAP_AUTH"; return 1)
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
				(echo "Failed to update LDAP auth source $LDAP_AUTH_NAME"; return 1)
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
			  exit 0
			end
			exit 1
		EOF
		)"
		until echo "$LDAP_CHECK" | ruby; do
			echo "Waiting for available LDAP server $LDAP_HOST:$LDAP_PORT and user $LDAP_USER_DN" >&2
			sleep 3
		done
	fi

	chown -R redmine:redmine files log public/plugin_assets || return 1
}

# Waits until database is available
waitForDB() {
	until ERROR=$(echo "SELECT 1;" | gosu redmine rails db -p 2>&1); do
		echo "Waiting for database $DB_ADAPTER://$DB_USERNAME@$DB_HOST:$DB_PORT/$DB_DATABASE: $ERROR"
		ERROR=
		sleep 1
	done
}

backup() {
	([ "$DB_ADAPTER" = postgresql ] || (echo "Works with postgresql only (algorythm container)" >&2; false)) &&
	([ "$1" ] || (echo "Usage: backup DESTINATION" >&2; false)) &&
	([ ! -f "$1" ] || (echo "Backup file $1 already exists" >&2; false)) &&
	([ ! -f /var/run/restore.pid ] || (echo "Cannot backup: Restore action in progress" >&2; false)) &&
	waitForDB &&
	BACKUP_ID="redmine-backlogs_$(date +'%y-%m-%d_%H-%M-%S')" &&
	BAK_TMP_DIR=$(mktemp -d) &&
	BAK_DIR=$BAK_TMP_DIR/$BACKUP_ID &&
	SQL_FILE=$BAK_DIR/redmine-postgres.sql &&
	mkdir $BAK_DIR || (rm -rf $BAK_TMP_DIR; false) &&
	sendDBBackupCommand dump-plain > $SQL_FILE &&
	tail -3 $SQL_FILE | grep -qx '\-\- PostgreSQL database dump complete' &&
	cp -r files $BAK_DIR/files &&
	tar -cjf "$1" -C $BAK_TMP_DIR $BACKUP_ID \
		|| (echo 'Backup failed' >&2; false)
	STATUS=$?
	rm -rf $BAK_TMP_DIR 2>/dev/null
	return $STATUS
}

restore() {
	([ "$DB_ADAPTER" = postgresql ] || (echo "Works with postgresql only (algorythm container)" >&2; false)) &&
	([ "$1" ] || (echo "Usage: restore BACKUP" >&2; false)) &&
	waitForDB &&
	echo $$ > /var/run/restore.pid &&
	stopCommand &&
	EXTRACT_DIR=$(mktemp -d) &&
	tar -xjf "$1" -C $EXTRACT_DIR &&
	BACKUP_ID="$(ls $EXTRACT_DIR | head -1)" &&
	SQL_FILE="$EXTRACT_DIR/$BACKUP_ID/redmine-postgres.sql" &&
	FILES_DIR="$EXTRACT_DIR/$BACKUP_ID/files" &&
	(([ -f "$SQL_FILE" ] && [ -d "$FILES_DIR" ]) || (echo 'Invalid backup formmat' >&2; false)) &&
	SQL_RESTORE_RESULT="$(sendDBBackupCommand restore-plain "$SQL_FILE")" &&
	echo "$SQL_RESTORE_RESULT" >&2 &&
	echo "$SQL_RESTORE_RESULT" | grep -qx 'Restored successfully' &&
	rm -rf files/* &&
	find "$FILES_DIR" -mindepth 1 -maxdepth 1 | while read FILE; do mv "$FILE" files || return 1; done &&
	chown -R redmine:redmine files &&
	INSTALL_MIGRATE=true && # enforce DB migration after restored
	INSTALL_DEFAULT_DATA=false && # Avoid insertion of default data
	migrateRedmine
	STATUS=$?
	rm -rf $EXTRACT_DIR 2>/dev/null
	rm -f /var/run/restore.pid
	return $STATUS
}

sendDBBackupCommand() {
	(
		cat <<-EOF
			$1
			$DB_DATABASE
			$DB_USERNAME
			$DB_PASSWORD
		EOF
		[ ! "$2" ] || cat "$2"
	) | nc $DB_HOST $DB_BACKUP_PORT
}

# Runs the provided command until it succeeds.
# Takes the error message to be displayed if it doesn't succeed as first argument.
awaitSuccess() {
	MSG="$1"
	shift
	until $@ >/dev/null 2>/dev/null; do
		[ ! "$MSG" ] || echo "$MSG" >&2
		sleep 3
	done
}

# Tests if the provided PID is terminated
isProcessTerminated() {
	! ps -o pid | grep -wq ${1:-0}
}

runCommand() {
	RUN_COMMAND="$(cat /var/run/run-command)" &&
	gosu redmine $RUN_COMMAND & # TODO: terminate on failure
	echo $! > /var/run/run-command.pid
	wait
}

stopCommand() {
	CMD_PID="$(cat /var/run/run-command.pid 2>/dev/null)"
	kill "$CMD_PID" 2>/dev/null
	awaitSuccess '' isProcessTerminated "$CMD_PID"
}

testContainerStarted() {
	! ps -C rails -C thin -C rake >/dev/null || (echo "Can be run as container start command only" >&2; false)
}

case "$1" in
	rails|thin|rake)
		testContainerStarted &&
		rm -f /var/run/restore.pid &&
		touch /var/run/run-command /var/run/command.pid &&
		chown root:root /var/run/run-command /var/run/command.pid &&
		chmod 0600 /var/run/run-command /var/run/command.pid &&
		echo "$@" > /var/run/run-command &&
		setupRedmine || exit 1
		while true; do
			runCommand || exit 2 # Run command in endless loop to handle backup restore actions that terminate 
			awaitSuccess 'Waiting for backup restore action to complete' [ ! -f /var/run/restore.pid ]
		done
	;;
	sh|backup|restore)
		$@
		exit $?
	;;
	*)
		echo "Usage: thin start|rails ...|rake ...|sh|backup DEST|restore SRC" >&2
	;;
esac
