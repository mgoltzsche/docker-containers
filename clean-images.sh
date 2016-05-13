#!/bin/sh

docker images | grep -E '^<none>' | grep -Eo '[a-z0-9]{12}' | xargs docker rmi -f
