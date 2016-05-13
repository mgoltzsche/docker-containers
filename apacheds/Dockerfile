FROM java:8-jre-alpine
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV APACHEDS_VERSION 2.0.0-M21
ENV LDAP_DOMAIN algorythm.de

# Add gosu for easy step-down from root
# and tini for signal processing (graceful container termination) and zombie killing
# (Install all in one RUN block to keep image small without build utils)
ENV GOSU_VERSION 1.7
ENV TINI_VERSION v0.9.0
RUN set -x \
	&& apk add --no-cache --update curl gnupg \
	&& curl -fSL -o /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64" \
	&& curl -fSL -o /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true \
	\
	&& curl -fSL -o /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static" \
	&& curl -fSL -o /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 6380DC428747F6C393FEACA59A84159D7001A4E5 \
	&& gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini \
	&& rm -r "$GNUPGHOME" /usr/local/bin/tini.asc \
	&& chmod +x /usr/local/bin/tini \
	&& tini -h \
	&& apk del --purge curl gnupg

# Create apacheds user and group
RUN addgroup apacheds && adduser -S -G apacheds apacheds

# Download and install apacheds
RUN wget -O apacheds.tar.gz http://apache.openmirror.de/directory/apacheds/dist/$APACHEDS_VERSION/apacheds-$APACHEDS_VERSION.tar.gz \
	&& tar -xzf apacheds.tar.gz \
	&& mv apacheds-$APACHEDS_VERSION /apacheds \
	&& mkdir /apacheds/ldif \
	&& mv /apacheds/instances/default/conf/config.ldif /apacheds/ldif/default-config.ldif \
	&& chown -R apacheds:apacheds /apacheds \
	&& echo -n 'secret' > /etc/apachedspw \
	&& chmod 400 /etc/apachedspw \
	&& rm apacheds.tar.gz \
	&& rm /apacheds/bin/*.bat

# Install bash and openldap-clients
RUN apk add --no-cache --update bash openldap-clients

# Add configuration and starter
ADD config/reset-admin-password.sh /apacheds/bin/
ADD config/setup-instance.sh /apacheds/bin/
ADD config/consul-apacheds-service.json /consul/config/local/apacheds.json
ADD config/algorythm-backup.ldif /apacheds/ldif/
ADD entrypoint.sh /
RUN chmod 544 /entrypoint.sh \
	&& chmod 700 /apacheds/bin/reset-admin-password.sh \
	&& chmod 544 /apacheds/bin/setup-instance.sh \
	&& chmod 444 /consul/config/local/apacheds.json

EXPOSE 10389 10636

WORKDIR /apacheds
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["run"]
