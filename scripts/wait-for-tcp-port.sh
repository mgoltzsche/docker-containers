#!/bin/sh
if [ $# -lt 2 ]; then
	echo "Usage: $0 HOST PORT [COMMAND]" >&2
	exit 1
fi

CHECKCMD="timeout 1 bash -c 'cat < /dev/null > /dev/tcp/$1/$2'"

while true; do
	if nc -h 2>/dev/null >/dev/null; then
		if nc -vzw1 "$1" "$2" 2>/dev/null; then
			break
		fi
	else
		if timeout 1 bash -c "</dev/tcp/$1/$2" 2>/dev/null; then
			break
		fi
	fi
	echo "Waiting for service $1:$2 to become available"
	sleep 1
done

if [ $# -gt 2 ]; then
	shift
	shift
	"$@" || exit $?
fi
