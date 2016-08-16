FROM debian:jessie
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV HHVM_VERSION=jessie-lts-3.12

# Install HHVM
RUN DEBIAN_FRONTEND=noninteractive \
	&& set -x \
	apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0x5a16e7281be7a449 \
	&& echo deb http://dl.hhvm.com/debian $HHVM_VERSION main > /etc/apt/sources.list.d/hhvm.list \
	&& apt-get update \
	&& apt-get install -y --force-yes --no-install-recommends hhvm php5-pgsql ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* /etc/hhvm/* /var/log/hhvm/*

# Add gosu for easy step-down from root
ENV GOSU_VERSION 1.9
RUN set -x \
	&& curl -fSL -o /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64" \
	&& curl -fSL -o /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64.asc" \
	&& export GNUPGHOME=$(mktemp -d) \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -r $GNUPGHOME /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true

# TODO: add hhvm pgsql extension from 3rd party: https://github.com/PocketRent/hhvm-pgsql/tree/releases (https://docs.hhvm.com/hhvm/extensions/introduction#dynamically-loaded-extensions)

RUN chown -R www-data:www-data /var/run/hhvm
RUN mkdir -m 770 /apps && chown www-data:www-data /apps

WORKDIR /apps

ADD server.ini /etc/hhvm/
ADD entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["hhvm", "-m", "server", "-c", "/etc/hhvm/server.ini"]
