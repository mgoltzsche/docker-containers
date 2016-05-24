FROM centos:7
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>
RUN yum -y update \
	&& yum install -y 389-ds-base \
	&& yum clean all
ADD entrypoint.sh /
ENTRYPOINT ["./entrypoint.sh"]
CMD ["dirsrv"]
