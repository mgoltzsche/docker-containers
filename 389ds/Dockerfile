# fedora:24 supports nsslapd-logging-backend config option - centos:7 not
FROM fedora:24
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>
RUN yum update -y \
	&& yum install -y 389-ds-base bzip2 rsyslog hostname procps-ng findutils \
	&& yum clean all
RUN rm /var/lock
EXPOSE 389

VOLUME /var/lib/dirsrv
VOLUME /backup

ADD entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ns-slapd"]
