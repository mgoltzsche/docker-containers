FROM java:8-jre-alpine
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV NEXUS_VERSION 3.0.1-01

# Create nexus user and group
RUN addgroup nexus && adduser -S -D -G nexus nexus -h /data -H -s /sbin/nologin

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
	&& tini -h >/dev/null \
	&& apk del --purge gnupg

# Download and install Nexus OSS
RUN set -x \
	&& apk add --no-cache --update gnupg \
	&& wget -O nexus.tar.gz http://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-unix.tar.gz \
	&& wget -O nexus.tar.gz.asc http://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-unix.tar.gz.asc \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 8DD1BDFD \
	&& gpg --batch --verify nexus.tar.gz.asc nexus.tar.gz \
	&& tar -xzf nexus.tar.gz \
	&& mv nexus-$NEXUS_VERSION /nexus \
	&& mkdir -m 750 /data \
	&& chown -R nexus:nexus /nexus /data \
	&& rm -r /nexus/data \
	&& sed -Ei 's/^(-Dkaraf\.data|-Djava.io.tmpdir)=data/\1=\/data/' /nexus/bin/nexus.vmoptions \
	&& rm -r "$GNUPGHOME" nexus.tar.gz nexus.tar.gz.asc \
	&& apk del --purge gnupg

# Add configuration and starter
ADD entrypoint.sh /
RUN chmod 544 /entrypoint.sh

EXPOSE 8081
VOLUME /data

WORKDIR /nexus
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["nexus", "run"]
