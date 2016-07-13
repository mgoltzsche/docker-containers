FROM centos:7
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>
RUN yum update -y \
	&& yum install -y 389-ds-base bzip2 \
	&& yum clean all

EXPOSE 389

VOLUME /var/lib/dirsrv
VOLUME /backup

ADD entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ns-slapd"]
