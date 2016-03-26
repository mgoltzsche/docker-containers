# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/apacheds:v1 --rm .

run:
	# Run apacheds container
	docker run algorythm/apacheds:v1
	# show container log
#	docker logs 6acfc613c604
	# execute command interactivly on running container
#	docker exec -it consul /bin/bash

bash:
	# Run bash in container interactively
	docker run -it -p 10389:10389 algorythm/apacheds:v1 bash
