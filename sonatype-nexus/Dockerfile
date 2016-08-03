FROM java:8-jre-alpine
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV NEXUS_VERSION 2.13.0-01

# Add gosu for easy step-down from root
# and tini for signal processing (graceful container termination) and zombie killing
# (Install all in one RUN block to keep image small without build utils)
ENV GOSU_VERSION 1.9
ENV TINI_VERSION v0.9.0
RUN set -x \
	&& apk add --no-cache --update gnupg \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64" \
	&& wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true \
	\
	&& wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static" \
	&& wget -O /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 6380DC428747F6C393FEACA59A84159D7001A4E5 \
	&& gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini \
	&& rm -r "$GNUPGHOME" /usr/local/bin/tini.asc \
	&& chmod +x /usr/local/bin/tini \
	&& tini -h \
	&& apk del --purge gnupg

# Create nexus user and group
RUN addgroup nexus && adduser -S -G nexus nexus

# Download and install Nexus OSS
RUN wget -O nexus-bundle.tar.gz download.sonatype.com/nexus/oss/nexus-${NEXUS_VERSION}.war \
	&& tar -xzf nexus-bundle.tar.gz \
	&& mv nexus-$NEXUS_VERSION /nexus \
	&& mkdir nexus-work \
	&& chown -R nexus:nexus /nexus /nexus-work \
	&& rm nexus-bundle.tar.gz /nexus/bin/*.bat

# Add configuration and starter
ADD entrypoint.sh /
RUN chmod 544 /entrypoint.sh

EXPOSE 8080

WORKDIR /nexus
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["start"]
