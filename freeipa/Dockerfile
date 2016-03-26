FROM debian:jessie
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>
RUN apt-get update -q && \
	apt-get upgrade -y
RUN DEBIAN_FRONTEND='noninteractive' apt-get install -y sssd-ipa && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
