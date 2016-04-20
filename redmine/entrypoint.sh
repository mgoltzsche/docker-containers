#!/bin/sh

case "$1" in rails|thin|rake)
	# Configure DB connection if not mounted as volume
	if [ ! -f './config/database.yml' ]; then
		if [ "$POSTGRES_PORT_5432_TCP" ]; then
			# Configure postgres if defined
			DB_ADAPTER='postgresql'
			DB_HOST="${POSTGRES_PORT_5432_TCP_HOST:-postgres}"
			DB_PORT="${POSTGRES_PORT_5432_TCP_PORT:-5432}"
			DB_USERNAME="${POSTGRES_ENV_POSTGRES_USER:-postgres}"
			DB_PASSWORD="${POSTGRES_ENV_POSTGRES_PASSWORD}"
			DB_DATABASE="${POSTGRES_ENV_POSTGRES_DB:-$username}"
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

	# Migrate DB
	if [ "$1" != 'rake' -a -z "$REDMINE_NO_DB_MIGRATE" ]; then
		echo "Migrating database. Avoid this by setting REDMINE_NO_DB_MIGRATE=true" >&2
		gosu redmine rake db:migrate &&
		gosu redmine rake redmine:plugins:migrate || exit 3
	fi

	# Insert default configuration data when unconfigured
	if [ -z $(echo "SELECT * FROM trackers;" | rails db -p) ] && [ -z "$REDMINE_NO_DEFAULT_DATA" ]; then
		echo "Inserting default configuration data. Avoid this by setting REDMINE_NO_DEFAULT_DATA=true" >&2
		gosu redmine rake redmine:load_default_data &&
		gosu redmine rake tmp:cache:clear &&
		gosu redmine rake tmp:sessions:clear &&
		gosu redmine rake redmine:backlogs:install \
			corruptiontest=true \
			labels=true \
			story_trackers=Feature \
			task_tracker=Task ||
		exit 4
		echo "SELECT role_id,(SELECT id FROM trackers WHERE name='Task'),old_status_id,new_status_id FROM workflows WHERE type='WorkflowTransition' AND tracker_id=(SELECT id FROM trackers WHERE name='Feature');" | \
			rails db --mode list 2>/dev/null | \
			sed -e 's/\|/,/g' -e 's/$/);/' | \
			xargs -n1 echo "INSERT INTO workflows(type,assignee,author,role_id,tracker_id,old_status_id,new_status_id) VALUES('WorkflowTransition','f','f'," | \
			gosu redmine rails db -p ||
		echo "Failed to copy 'Feature' tracker workflow to 'Task' tracker workflow. You may have to create the workflow yourself to be able to interact with a backlogs task board" >&2
	fi

	# TODO: Configure LDAP

	chown -R redmine:redmine files log public/plugin_assets
	rm -f tmp/pids/server.pid

	set -- gosu redmine "$@"
	;;
esac

exec "$@"
