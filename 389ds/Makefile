# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/389ds:latest --rm .

run:
	# Run container
	docker run -h ldap.algorythm.de -p "389:389" \
		-e "LDAP_USER_DN_REDMINE=cn=redmine,ou=Special Users,dc=algorythm,dc=de" \
		-e "LDAP_USER_PW_REDMINE=Secret123" \
		algorythm/389ds:latest

cat:
	# Run container
	docker run -h ldap.algorythm.de -p "389:389" algorythm/389ds:latest ldapsearch -b dc=algorythm,dc=de

sh:
	# Run shell in container interactively
	docker run -h ldap.algorythm.de -it algorythm/389ds:latest bash

join:
	# Execute interactive bash on running container
	docker exec -it `docker ps | grep algorythm/389ds | cut -d ' ' -f 1` /bin/bash

kill:
	docker kill `docker ps | grep algorythm/389ds | cut -d ' ' -f 1`
