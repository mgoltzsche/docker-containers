#!/bin/sh

if [ $# -lt 2 ]; then
	echo "Usage $0 ENVIRONMENT COMMAND" >&2
	echo "  ENVIRONMENT = dev|prod|test" >&2
	exit 1
fi

ENV_TYPE="$1"

export $(find . -name "*.$ENV_TYPE.env" | xargs cat | grep -E '^[^#=]+=.*')
shift
docker-compose $@
