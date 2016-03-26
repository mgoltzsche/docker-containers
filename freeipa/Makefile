# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/freeipa:4 --rm .

run:
	# Run apacheds container
	docker run algorythm/freeipa:4
	# show container log
#	docker logs 6acfc613c604
	# execute command interactivly on running container
#	docker exec -it consul /bin/bash

bash:
	# Run bash in container interactively
	docker run -it algorythm/freeipa:4 bash
