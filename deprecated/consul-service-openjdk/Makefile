# Install docker: wget -qO- https://get.docker.com/ | sh

all: build

build:
	# Build docker image from Dockerfile in this directory
	docker build -t algorythm/consul-service-openjdk:8 --rm .

java-version:
	# Run java in container and show version
	docker run algorythm/consul-service-openjdk:8 java -version

bash:
	# Run bash in container interactively
	docker run -it algorythm/consul-service-openjdk:8 bash
