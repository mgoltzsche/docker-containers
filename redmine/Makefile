# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/redmine-backlogs:latest --rm .

run:
	# Run container
	docker run -p 3000:3000 -h redmine.algorythm.de algorythm/redmine-backlogs:latest

db:
	docker run -it -p 3000:3000 -h redmine algorythm/redmine-backlogs:latest rails db -p
	# SQL to show all table names: SELECT name FROM sqlite_master WHERE type='table'

logs:
	# Show log of running container
	docker logs `docker ps | grep redmine-backlogs | cut -d ' ' -f 1`

sh:
	# Run shell in container interactively
	docker run -it -h redmine algorythm/redmine-backlogs:latest /bin/sh

join:
	# Execute interactive shell on running container
	docker exec -it `docker ps | grep redmine-backlogs | cut -d ' ' -f 1` /bin/sh
