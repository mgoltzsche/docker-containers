all: build

build:
	docker build -t algorythm/mail:latest --rm .

run:
	# Run container with all services
	docker run -p 25:25 -h mail.algorythm.de -e "LDAP_STARTUP_CHECK_ENABLED=false" algorythm/mail:latest run

sh:
	# Start container with interactive shell
	docker run -it -v `pwd`/work:/work -h mail.algorythm.de algorythm/mail:latest /bin/sh

join:
	# Execute interactive shell on running container
	docker exec -it `docker ps | grep mail | cut -d ' ' -f 1` /bin/sh

kill:
	docker kill `docker ps | grep algorythm/mail | cut -d ' ' -f 1`
