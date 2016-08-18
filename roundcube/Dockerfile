FROM algorythm/hhvm:latest
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV ROUNDCUBE_VERSION 1.1.5

RUN set -x \
	&& curl -fSL -o roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz \
	&& curl -fSL -o roundcube.tar.gz.asc https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz.asc \
	&& export GNUPGHOME=$(mktemp -d) \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 41C4F7D5 \
	&& gpg --batch --verify roundcube.tar.gz.asc roundcube.tar.gz \
	&& tar -xzf roundcube.tar.gz \
	&& mv roundcubemail-${ROUNDCUBE_VERSION} /roundcube \
	&& rm -rf $GNUPGHOME roundcube.tar.gz roundcube.tar.gz.asc

RUN echo "\$config['mime_types'] = '/etc/hhvm/mime.types';" >> /roundcube/config/defaults.inc.php

RUN chown -R www-data:www-data /roundcube

ADD entrypoint.sh /conf.d/configure-roundcube.sh

WORKDIR /roundcube
