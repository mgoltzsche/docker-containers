FROM algorythm/hhvm:latest
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

RUN DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/*

ENV ROUNDCUBE_VERSION 1.1.5

RUN set -x \
	&& wget -O roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz \
	&& wget -O roundcube.tar.gz.asc https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz.asc \
	&& export GNUPGHOME=$(mktemp -d) \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 41C4F7D5 \
	&& gpg --batch --verify roundcube.tar.gz.asc roundcube.tar.gz \
	&& tar -xzf roundcube.tar.gz \
	&& mv roundcubemail-${ROUNDCUBE_VERSION} /roundcube \
	&& rm -rf $GNUPGHOME roundcube.tar.gz roundcube.tar.gz.asc

RUN chown -R www-data:www-data /roundcube

WORKDIR /roundcube
