# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/mailpile:latest --rm .

run:
	# Run container
	docker run -h webmail -p 8082:8082 algorythm/mailpile:latest

logs:
	# Show log of running container
	docker logs `docker ps | grep algorythm/mailpile | cut -d ' ' -f 1`

sh:
	# Run bash in container interactively
	docker run -it -h webmail algorythm/mailpile:latest /bin/sh

join:
	# Execute interactive bash on running container
	docker exec -it `docker ps | grep algorythm/mailpile | cut -d ' ' -f 1` /bin/sh

kill:
	# Kill running container
	docker kill `docker ps | grep algorythm/mailpile | cut -d ' ' -f 1`
