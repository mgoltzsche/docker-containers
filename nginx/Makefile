# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/nginx:latest --rm .

run:
	# Run container
	docker run -p 80:80 -h web.algorythm.de algorythm/nginx:latest

logs:
	# Show log of running container
	docker logs `docker ps | grep algorythm/nginx | cut -d ' ' -f 1`

sh:
	# Run shell in container interactively
	docker run -it -h web.algorythm.de algorythm/nginx:latest /bin/sh

join:
	# Execute interactive shell on running container
	docker exec -it `docker ps | grep algorythm/nginx | cut -d ' ' -f 1` /bin/sh

kill:
	docker kill `docker ps | grep algorythm/nginx | cut -d ' ' -f 1`
