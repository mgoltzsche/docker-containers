# fedora:24 supports nsslapd-logging-backend config option - centos:7 not
FROM fedora:24
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>
# Install 389ds, rsyslog, hostname procps-ng (ps), findutils (find, xargs), tar, bzip2
RUN yum update -y \
	&& yum install -y 389-ds-base rsyslog hostname procps-ng findutils tar bzip2 \
	&& yum clean all \
	&& rm /var/lock

EXPOSE 389

VOLUME /var/lib/dirsrv
VOLUME /backup

ADD entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ns-slapd"]
