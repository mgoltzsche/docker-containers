# Forked from https://github.com/hashicorp/docker-consul/tree/master/0.6

# build docker image from Dockerfile in this directory
docker build -t algorythm/consul:v1 .


# Run gliderlabs docker agent
docker run gliderlabs/consul agent -server -bootstrap

# run single dev server (as daemon: -d)
docker run -p 8400:8400 -p 8500:8500 -p 8600:53/udp -h consul-server algorythm/consul:v1 server -bootstrap -ui -client=172.17.0.2

# run joined client
docker run -h consul-client algorythm/consul:v1 client -retry-join=172.17.0.2

# show running containers
docker ps

# show container log
docker logs 6acfc613c604

# execute command interactivly on running container
docker exec -it consul /bin/sh

# stop running daemon
docker stop 6acfc613c604
