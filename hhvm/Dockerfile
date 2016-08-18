FROM debian:jessie
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV HHVM_VERSION=jessie-lts-3.12
ENV HHVM_PGSQL_VERSION 3.12.0

# Install HHVM with pgsql extension
RUN DEBIAN_FRONTEND=noninteractive \
	&& set -x \
	apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0x5a16e7281be7a449 \
	&& echo deb http://dl.hhvm.com/debian $HHVM_VERSION main > /etc/apt/sources.list.d/hhvm.list \
	&& apt-get update \
	&& apt-get install -y --force-yes --no-install-recommends hhvm hhvm-dev libpq5 libpq-dev ca-certificates curl \
	&& git clone git://github.com/PocketRent/hhvm-pgsql --branch $HHVM_PGSQL_VERSION --single-branch --depth=1 \
	&& cd hhvm-pgsql \
	&& hphpize \
	&& cmake . \
	&& make \
	&& mv pgsql.so /usr/lib/hhvm/pgsql.so \
	&& apt-get purge -y --force-yes hhvm-dev libpq-dev \
	&& apt-get autoremove --purge -y --force-yes \
    && rm -rf /var/lib/apt/lists/* /etc/hhvm/* /var/log/hhvm/* /hhvm-pgsql

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

RUN curl -fSL -o /etc/hhvm/mime.types http://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
#ENV MAGIC /etc/hhvm/mime.types

RUN chown -R www-data:www-data /var/run/hhvm
RUN mkdir -m 770 /apps && chown www-data:www-data /apps
RUN mkdir -m 775 /conf.d

WORKDIR /apps

ADD server.ini /etc/hhvm/
ADD entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["hhvm", "-m", "server", "-c", "/etc/hhvm/server.ini"]
