#!/bin/bash

PG_USERS="$(set | grep -Eo '^PG_USER_[^=]+' | sed 's/^PG_USER_//')"

if [ "$PG_USERS" ]; then
	# Wait for postgres start
	until su postgres -c "psql -c 'SELECT 1'" >/dev/null; do
		echo 'Waiting for PostgreSQL to become available'
		sleep 1
	done

	for PG_USER_KEY in "$PG_USERS"; do
		PG_USER=$(echo -n "$PG_USER_KEY" | tr '[:upper:]' '[:lower:]') # User name lower case
		PG_USER_PASSWORD=$(eval "echo \$PG_USER_$PG_USER_KEY")
		PG_USER_DATABASE="$PG_USER"
		if ! echo "SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'" | su postgres -c 'psql -tA' | grep -q 1; then
			# Create user
			echo "Adding PostgreSQL user: $PG_USER"
			su postgres -c "createuser '$PG_USER'" || exit 1
		else
			echo "Resetting PostgreSQL user's password: $PG_USER"
		fi
		# Reset user password
		echo "ALTER USER $PG_USER WITH ENCRYPTED PASSWORD '$PG_USER_PASSWORD'" | su postgres -c psql >/dev/null || exit 1
		if ! su postgres -c 'psql -lqt' | cut -d \| -f 1 | grep -qw "$PG_USER_DATABASE"; then
			# Create user database
			echo "Adding PostgreSQL database: $PG_USER_DATABASE"
			su postgres -c "createdb -T template0 -O '$PG_USER' '$PG_USER_DATABASE'" || exit 1
		fi
	done
fi
