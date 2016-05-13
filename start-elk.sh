#!/bin/sh

docker run --volume=/var/run/docker.sock:/tmp/docker.sock logstash:5 logstash -e 'input { stdin { } } output { stdout { } }'
