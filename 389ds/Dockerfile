FROM debian:jessie
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>
RUN apt-get update -q && \
	apt-get upgrade -y
RUN DEBIAN_FRONTEND='noninteractive' apt-get install -y 389-ds-base && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ADD config/entrypoint.sh /
