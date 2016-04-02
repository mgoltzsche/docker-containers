#!/bin/sh
####################################################################
# Takes an input file containing placeholders in the format #{key} #
# and substitutes them with the key value pairs provided.          #
# Usage: render-tpl TEMPLATEFILE PARAM1=VALUE1 [KEY2=VALUE2 [...]] #
####################################################################

USAGE="Usage $0 TEMPLATEFILE KEY1=VAL1 [KEY2=VAL2 ...]"

if [ $# -lt 2 ]; then # Check param size
	echo "$USAGE" >&2
	exit 1
fi

TPL_FILE="$1"
REPLACED=$(cat "$1") # Load template file
shift

while test $# -gt 0; do # Replace parameter placeholders
	KEY=$(echo -n "$1" | grep -Eom 1 '^[^=]+')
	VALUE=$(echo -n "$1" | awk -v RS="" '{gsub (/\n/,"\\n")}1' | sed -E 's/^[^=]+=//' | sed -E 's/[/\\&]/\\\0/g')
	#                      ^ Replace line break with \n          ^ Extract value        ^ Escape /\& with \

	if [ $(echo "$1" | grep -Eic '^[a-z0-9_\.]+=.*') -eq 0 ]; then
		echo "Invalid parameter: $1" >&2
		echo "$USAGE" >&2
		exit 1
	fi

	ORIGINAL=$REPLACED
	REPLACED=$(echo "$REPLACED" | sed "s/#{$KEY}/$VALUE/g")

	if [ $? -ne 0 ]; then
		echo "Substitution of $KEY in template $TPL_FILE with '$VALUE' failed" >&2
		exit 1
	fi

	if [ "$ORIGINAL" = "$REPLACED" ]; then
		echo "WARN: Parameter $KEY is not declared in template $TPL_FILE" >&2
	fi
	shift
done

PARAMS_UNDEF=$(echo "$REPLACED" | grep -Eio '#\{[a-z0-9_\.]+\}' | cut -d '{' -f 2 | cut -d '}' -f 1 | sort | uniq)

if [ $(echo $PARAMS_UNDEF | grep -Ec '[^ ]') -ne 0 ]; then # Check undefined params
	rm -f $TMP_FILE
	echo "Undefined parameters:" >&2
	echo "$PARAMS_UNDEF" | xargs -n 1 echo '  ' >&2
	exit 1
fi

echo "$REPLACED"
