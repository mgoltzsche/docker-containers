#!/bin/bash

DOCKER_COMPOSE_VERSION='1.8.0'

# Test if root
[ "$(id -u)" = "0" ] || (echo "Must be run as root to install docker & docker-compose" >&2; false) || exit 1

# Install docker engine if not yet installed
if ! dpkg -l | grep -Eq '^ii\s+docker-engine'; then
	echo 'Installing docker engine ...'
	wget -qO- https://get.docker.com/ | sh || (echo 'Docker installation failed' >&2; false) || exit 1
fi

# Install docker compose if not yet installed
if ! docker-compose -v 2>/dev/null | grep -Eq "^docker-compose version $DOCKER_COMPOSE_VERSION,"; then
	echo 'Installing/updating docker compose'
	wget -O /usr/local/bin/docker-compose https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-`uname -s`-`uname -m` &&
	chmod +x /usr/local/bin/docker-compose
fi
