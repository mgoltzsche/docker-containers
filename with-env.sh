#!/bin/bash

if [ $# -lt 2 ]; then
	echo "Usage $0 ENVIRONMENT COMMAND" >&2
	echo "  ENVIRONMENT = dev|prod|test" >&2
	exit 1
fi

ENV_TYPE="$1"
shift

# (find . -name "*.$ENV_TYPE.env" -print0 | xargs -0 cat | grep -E '^[^#=]+=.*' && echo docker-compose $@) | xargs env # doesn't work since it occupies stdin

IFS=$'\n' # Use line break as internal field separator
ENVVARS=$(find . -name "*.$ENV_TYPE.env" -print0 | xargs -0 cat | grep -EZ '^[^#=]+=.*')

env ${ENVVARS} docker-compose $@
