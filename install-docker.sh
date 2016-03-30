#!/bin/bash

DOCKER_COMPOSE_VERSION='1.7.0-rc1'

# Install docker engine if not yet installed
if [ $(dpkg -l | grep -c docker-engine) -eq 0 ]; then
	echo 'Installing docker engine'
	wget -qO- https://get.docker.com/ | sh
	if [ $? -ne 0 ]; then
		echo 'Docker installation failed' >&2
		exit 1
	fi
fi

# Install or update docker compose
echo 'Installing/updating docker compose'
curl -L https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose &&
chmod +x /usr/local/bin/docker-compose
