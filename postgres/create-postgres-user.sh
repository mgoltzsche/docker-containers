#!/bin/sh
if [ $# -lt 1 ]; then
	echo "Usage: $0 USER" >&2
	exit 1
fi

PGUSER="$1"

if ! echo "SELECT 1 FROM pg_roles WHERE rolname='$PGUSER'" | su postgres -c 'psql -tA' | grep -q 1; then
	su postgres -c "createuser -D '$PGUSER'"
fi
