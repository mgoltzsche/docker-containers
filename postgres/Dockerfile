FROM alpine:3.5
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

# Install rsyslog & postgres
RUN apk add --no-cache --update postgresql

# Add gosu for easy step-down from root (Install all in one RUN block to keep image small without build utils)
ENV GOSU_VERSION 1.10
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
	&& apk del --purge curl gnupg

# Modify default configuration
RUN sed -Ei "s/^#?(listen_addresses) ?=.*/\1 = '*'/" /usr/share/postgresql/postgresql.conf.sample \
	&& echo "log_destination='stderr'" >> /usr/share/postgresql/postgresql.conf.sample \
	&& echo "host all  all    0.0.0.0/0  md5" >> /usr/share/postgresql/pg_hba.conf.sample

EXPOSE 5432

ENV LANG en_US.utf8
ENV PGDATA /var/lib/postgresql/data
VOLUME  ["/var/lib/postgresql"]

RUN mkdir /entrypoint-initdb.d
ADD entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["postgres"]
