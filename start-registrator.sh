#!/bin/sh

docker run --name=registrator --net=host --volume=/var/run/docker.sock:/tmp/docker.sock gliderlabs/registrator:latest consul://172.18.0.2:8500
