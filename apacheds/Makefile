# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/apacheds:latest --rm .

run:
	# Run apacheds container
	docker run algorythm/apacheds:latest

logs:
	# Show log of running container
	docker logs `docker ps | grep apacheds | cut -d ' ' -f 1`

bash:
	# Run bash in container interactively
	docker run -it -p 10389:10389 algorythm/apacheds:latest bash

join:
	# Execute interactive bash on running container
	docker exec -it `docker ps | grep apacheds | cut -d ' ' -f 1` /bin/bash
