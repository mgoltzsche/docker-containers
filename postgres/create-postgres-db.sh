#!/bin/sh
if [ $# -lt 2 ]; then
	echo "Usage: $0 DBNAME OWNER" >&2
	exit 1
fi

#until su postgres -c "psql -c 'SELECT 1'" >/dev/null; do
#	echo 'Waiting for PostgreSQL to become available'
#	sleep 1
#done

DB="$1"
OWNER="$2"

if ! su postgres -c 'psql -lqt' | cut -d \| -f 1 | grep -qw "$DB"; then
	su postgres -c "createdb -T template0 -O '$OWNER' '$DB'"
fi

#echo "CREATE DATABASE $DB WITH \
#	OWNER = $OWNER \
#	ENCODING = 'UTF8' \
#	LC_CTYPE = 'en_US.utf8' \
#	LC_COLLATE = 'en_US.utf8' \
#	TEMPLATE = template0;" | su postgres -c psql
