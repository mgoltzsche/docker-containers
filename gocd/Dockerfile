FROM java:8-jre-alpine
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV GOCD_VERSION 16.8.0-3929

# Add user
RUN addgroup -g 3000 gocd && \
    adduser -u 3000 -S -D -G gocd gocd -h /var/gocd -H -s /sbin/nologin

# Install rsyslog, postfix and dovecot + ldap integration
RUN apk add --no-cache --update rsyslog ca-certificates

# Add gosu for easy step-down from root
# and tini for signal processing (graceful container termination) and zombie killing
# (Install all in one RUN block to keep image small without build utils)
ENV GOSU_VERSION 1.7
ENV TINI_VERSION v0.9.0
RUN set -x \
	&& apk add --update --no-cache curl gnupg \
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
	\
	&& curl -fSL -o go-server.zip https://download.go.cd/binaries/$GOCD_VERSION/generic/go-server-$GOCD_VERSION.zip \
	&& apk del --purge curl gnupg

RUN apk add --update --no-cache unzip bash \
	&& unzip go-server.zip \
	&& mv go-server-$(echo $GOCD_VERSION | sed -E 's/-[0-9]+$//') /go-server \
	&& rm /go-server/*.bat /go-server/*.cmd /go-server/*.init /go-server/stop-server.sh \
	&& chown -R gocd:gocd /go-server \
	&& chmod 755 /go-server \
	&& chmod 644 /go-server/* \
	&& chmod 544 /go-server/server.sh \
	&& rm go-server.zip

RUN mkdir -m 700 /var/gocd && chown gocd:gocd /var/gocd

EXPOSE 8080

ADD entrypoint.sh /
ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
CMD ["/go-server/server.sh"]
