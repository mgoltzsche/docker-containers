all: build

build:
	docker build -t algorythm/consul:latest --rm .

start-server:
	docker run -p 8400:8400 -p 8500:8500 -p 53:8600/udp -h consul-server algorythm/consul:latest server -bootstrap-expect 1 -ui -client=172.17.0.2 # Assuming container IP
	# To be able to recover from 1 node failure run 3 nodes
	# To be able to recover from 2 node failures run 5 nodes

start-client:
	docker run -h consul-client algorythm/consul:latest client -retry-join=172.17.0.2

sh:
	# Start container with interactive shell
	docker run -it algorythm/consul:latest /bin/sh

join:
	# Execute interactive shell on running container
	docker exec -it `docker ps | grep consul | cut -d ' ' -f 1` /bin/sh
