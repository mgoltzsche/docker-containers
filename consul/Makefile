all: build

build:
	docker build -t algorythm/consul:v1 --rm .

start-server:
	docker run -p 8400:8400 -p 8500:8500 -p 8600:53/udp -h consul-server algorythm/consul:v1 server -bootstrap-expect 1 -ui -client=172.17.0.2 # Assuming container IP
	# To be able to recover from 1 node failure run 3 nodes
	# To be able to recover from 2 node failures run 5 nodes

start-client:
	docker run -h consul-client algorythm/consul:v1 client -retry-join=172.17.0.2

sh:
	docker run -it algorythm/consul:v1 /bin/sh
	
