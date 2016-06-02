#!/bin/sh

if [ $# -lt 1 ]; then echo "Usage: $0 PREFIX1:PIPE1 [PREFIX2:PIPE2 ...]" >&2; exit 1; fi

for PIPE in $@; do
	if echo "$PIPE" | grep -Eo '.*:' >/dev/null && ! echo | sed -u 's/^/p/g' 2>/dev/null >&2; then echo "sed's -u option is not supported on this platform" >&2; exit 1; fi
	if [ -f $(echo "$PIPE" | cut -d : -f 2) ]; then echo "$PIPE already exists" >&2; exit 1; fi
done

if [ $# -eq 1 ]; then
	MAINPREFIX=$(echo "$1" | grep -Eo '.*:')
	MAINPIPE=$(echo "$1" | cut -d : -f 2)
	shift
else
	MAINPREFIX=
	MAINPIPE=/tmp/pipe-$(cat /proc/sys/kernel/random/uuid)
fi
PIPES=$@

catPipe() {
	if [ "$2" ]; then
		while true; do
			sed -u "s/^/$2/g" "$1" || exit 1 # -u option not available under alpine linux
		done
	else
		while true; do
			cat "$1" || exit 1
		done
	fi
}

mkdir -p $(dirname "$MAINPIPE") || exit 2
mkfifo "$MAINPIPE" || exit 2

CHILDPIDS=
for PIPE in $PIPES; do
	PREFIX=$(echo "$PIPE" | grep -Eo '.*:')
	PIPE=$(echo "$PIPE" | cut -d : -f 2)
	mkdir -p $(dirname "$PIPE")
	mkfifo "$PIPE"
	catPipe "$PIPE" "$PREFIX" &
	CHILDPIDS="$CHILDPIDS $!"
done

catPipe "$MAINPIPE" "$MAINPREFIX" &
CHILDPIDS="$CHILDPIDS $!"

terminatePipes() {
	trap : 1 2 3 15 # Disable signal listener
	# Wait for pipes to terminate
	for CHILDPID in $CHILDPIDS; do
		kill $CHILDPIDS 2>/dev/null
		while ps $CHILDPID >/dev/null; do sleep 1; done
	done
	# Remove pipes
	rm -rf "$MAINPIPE"
	for PIPE in $PIPES; do
		echo "$PIPE" | cut -d : -f 2 | xargs rm -rf
	done
}

trap terminatePipes 1 2 3 15 # SIGHUP SIGINT SIGQUIT SIGTERM
wait
