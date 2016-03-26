# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/389ds:1 --rm .

run:
	# Run apacheds container
	docker run algorythm/389ds:1
	# show container log
#	docker logs 6acfc613c604
	# execute command interactivly on running container
#	docker exec -it consul /bin/bash

bash:
	# Run bash in container interactively
	docker run -it algorythm/389ds:1 bash
