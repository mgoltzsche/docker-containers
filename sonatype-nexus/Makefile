# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/sonatype-nexus:latest --rm .

run:
	# Run container
	docker run -h repository.algorythm.de -p 8081:8081 -v `pwd`"/work:/data" algorythm/sonatype-nexus:latest

logs:
	# Show log of running container
	docker logs `docker ps | grep algorythm/sonatype-nexus | cut -d ' ' -f 1`

sh:
	# Run bash in container interactively
	docker run -it -h repository.algorythm.de algorythm/sonatype-nexus:latest /bin/sh

join:
	# Execute interactive bash on running container
	docker exec -it `docker ps | grep algorythm/sonatype-nexus | cut -d ' ' -f 1` /bin/sh

kill:
	# Kill running container
	docker kill `docker ps | grep algorythm/sonatype-nexus | cut -d ' ' -f 1`
