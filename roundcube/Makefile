# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/roundcube:latest --rm .

run:
	# Run container
	docker run -h webmail.algorythm.de -p 9000:9000 algorythm/roundcube:latest

logs:
	# Show log of running container
	docker logs `docker ps | grep algorythm/roundcube | cut -d ' ' -f 1`

sh:
	# Run bash in container interactively
	docker run -it -h webmail.algorythm.de algorythm/roundcube:latest /bin/bash

join:
	# Execute interactive bash on running container
	docker exec -it `docker ps | grep algorythm/roundcube | cut -d ' ' -f 1` /bin/bash

kill:
	# Kill running container
	docker kill `docker ps | grep algorythm/roundcube | cut -d ' ' -f 1`
