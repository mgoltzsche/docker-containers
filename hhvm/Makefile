# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/hhvm:latest --rm .

run:
	# Run container
	docker run -h hhvm -p 9000:9000 algorythm/hhvm:latest

logs:
	# Show log of running container
	docker logs `docker ps | grep algorythm/hhvm | cut -d ' ' -f 1`

sh:
	# Run bash in container interactively
	docker run -it -h hhvm algorythm/hhvm:latest /bin/bash

join:
	# Execute interactive bash on running container
	docker exec -it `docker ps | grep algorythm/hhvm | cut -d ' ' -f 1` /bin/bash

kill:
	# Kill running container
	docker kill `docker ps | grep algorythm/hhvm | cut -d ' ' -f 1`
