#!/bin/sh

# Remove all stopped containers
docker ps -a | grep -Eo '[a-z0-9]{12} ' | xargs docker rm
# Remove all unnamed images
docker images | grep -E '^<none>' | grep -Eo '[a-z0-9]{12}' | xargs docker rmi -f
