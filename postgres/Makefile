# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/postgres:latest --rm .

run:
	# Run container
	docker run -p 5432:5432 -e POSTGRES_PASSWORD=secret -e PG_USER_REDMINE=redsecret algorythm/postgres:latest

logs:
	# Show log of running container
	docker logs `docker ps | grep algorythm/postgres | cut -d ' ' -f 1`

sh:
	# Run shell in container interactively
	docker run -it algorythm/postgres:latest /bin/sh

join:
	# Execute interactive shell on running container
	docker exec -it `docker ps | grep algorythm/postgres | cut -d ' ' -f 1` /bin/sh
