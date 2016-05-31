FROM centos:7
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>
RUN yum -y update \
	&& yum install -y 389-ds-base bzip2 \
	&& yum clean all

# Add tini for signal processing (graceful container termination) and zombie killing
ENV TINI_VERSION v0.9.0
RUN set -x \
	&& curl -fSL -o /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static" \
	&& curl -fSL -o /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 6380DC428747F6C393FEACA59A84159D7001A4E5 \
	&& gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini \
	&& rm -r "$GNUPGHOME" /usr/local/bin/tini.asc \
	&& chmod +x /usr/local/bin/tini \
	&& tini -h

EXPOSE 389

VOLUME /var/lib/dirsrv

ADD ldap-client.sh /bin/ldap
ADD entrypoint.sh /
#ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ns-slapd"]
