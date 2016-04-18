#!/bin/sh

case "$1" in rails|thin|rake)
	if [ ! -f './config/database.yml' ]; then
		# Configure DB connection if not mounted as volume
		if [ "$POSTGRES_PORT_5432_TCP" ]; then
			# Configure postgres if defined
			DB_ADAPTER='postgresql'
			DB_HOST='postgres'
			DB_PORT="${POSTGRES_PORT_5432_TCP_PORT:-5432}"
			DB_USERNAME="${POSTGRES_ENV_POSTGRES_USER:-postgres}"
			DB_PASSWORD="${POSTGRES_ENV_POSTGRES_PASSWORD}"
			DB_DATABASE="${POSTGRES_ENV_POSTGRES_DB:-$username}"
			DB_ENCODING=utf8
		else
			# Configure sqlite as fallback
			echo "Warning: Using sqlite since no POSTGRES_PORT_5432_TCP environment variable specified" >&2
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
			rake generate_secret_token || exit 1
		fi
	fi

	# Migrate DB
	if [ "$1" != 'rake' -a -z "$REDMINE_NO_DB_MIGRATE" ]; then
		gosu redmine rake db:migrate || exit 1
	fi

	# Insert default configuration when unconfigured
	if [ -z $(echo "SELECT * FROM settings;" | rails db -p) ]; then
		# Insert default data
		gosu redmine bundle exec rake redmine:load_default_data &&
		# Configure redmine backlogs
		gosu redmine bundle exec rake tmp:cache:clear \
			&& gosu redmine bundle exec rake tmp:sessions:clear \
			&& gosu redmine bundle exec rake redmine:backlogs:install \
				corruptiontest=true \
				labels=true \
				story_trackers=Feature \
				task_tracker=Task \
			|| exit 1
	fi

	chown -R redmine:redmine files log public/plugin_assets
	rm -f tmp/pids/server.pid

	set -- gosu redmine "$@"
	;;
esac

exec "$@"
