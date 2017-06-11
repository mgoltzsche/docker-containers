all: build

build:
	docker build -t algorythm/gocd-server:latest --rm .

run:
	# Run container with all services
	docker run -p "8080:8080" algorythm/gocd-server:latest

sh:
	# Start container with interactive shell
	docker run -it -h mail.algorythm.de algorythm/gocd-server:latest /bin/sh

join:
	# Execute interactive shell on running container
	docker exec -it `docker ps | grep algorythm/gocd-server | cut -d ' ' -f 1` /bin/sh

kill:
	docker kill `docker ps | grep algorythm/gocd-server | cut -d ' ' -f 1`
