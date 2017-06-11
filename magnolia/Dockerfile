# Ruby 2.2 is the latest version supported by Redmine 2.6.9
FROM java:8-jre-alpine
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

# Create magnolia user and group
RUN addgroup -g 5000 magnolia && \
    adduser -u 5000 -S -D -G magnolia magnolia -h /data -H -s /sbin/nologin

# Add required binaries/libraries
#RUN apk add --update --no-cache 

# Add gosu for easy step-down from root
# and tini for signal processing (graceful container termination) and zombie killing
# (Install all in one RUN block to keep image small without build utils)
ENV GOSU_VERSION 1.10
ENV TINI_VERSION v0.13.2
RUN set -x \
	&& apk add --update --no-cache gnupg curl \
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
	&& tini -h >/dev/null \
	&& apk del --purge gnupg

# Download and extract Magnolia
ENV MAGNOLIA_PRODUCT magnolia-community-demo-bundle
ENV MAGNOLIA_VERSION 5.5.1
RUN set -x \
	&& apk add --update --no-cache unzip \
	&& curl -fSL -o magnolia.zip "https://nexus.magnolia-cms.com/content/repositories/magnolia.public.releases/info/magnolia/bundle/${MAGNOLIA_PRODUCT}/${MAGNOLIA_VERSION}/${MAGNOLIA_PRODUCT}-${MAGNOLIA_VERSION}-tomcat-bundle.zip" \
	&& unzip magnolia.zip \
	&& mkdir -p /opt \
	&& mv magnolia-$MAGNOLIA_VERSION/apache-tomcat-* /opt/magnolia \
	&& rm -rf magnolia-$MAGNOLIA_VERSION magnolia.zip \
	&& apk del --purge unzip

WORKDIR /opt/magnolia
VOLUME /data
EXPOSE 8080

ADD entrypoint.sh /
RUN chmod 544 /entrypoint.sh

ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
CMD ["run"]
