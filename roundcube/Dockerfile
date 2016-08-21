FROM algorythm/hhvm:latest
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

# Due to html class not found bug (https://github.com/facebook/hhvm/issues/5185) in HHVM RC 1.1.5 LTS cannot be used
# TODO: Use LTS when available
ENV ROUNDCUBE_VERSION 1.2.1

RUN set -x \
	&& curl -fSL -o roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz \
	&& curl -fSL -o roundcube.tar.gz.asc https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz.asc \
	&& export GNUPGHOME=$(mktemp -d) \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 41C4F7D5 \
	&& gpg --batch --verify roundcube.tar.gz.asc roundcube.tar.gz \
	&& tar -xzf roundcube.tar.gz \
	&& mv roundcubemail-${ROUNDCUBE_VERSION} /roundcube \
	&& rm -rf $GNUPGHOME roundcube.tar.gz roundcube.tar.gz.asc

RUN echo "\$config['mime_types'] = '/etc/mime.types';" >> /roundcube/config/defaults.inc.php
RUN rm -rf /roundcube/logs
RUN chown -R root:www-data /roundcube && chmod 770 /roundcube/temp
RUN mv /roundcube/installer /roundcube-installer
RUN mkdir -m 0755 /db && chown www-data:www-data /db
ADD entrypoint.sh /conf.d/configure-roundcube.sh

WORKDIR /roundcube
