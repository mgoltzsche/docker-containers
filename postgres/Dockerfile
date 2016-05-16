FROM postgres:9.5.2
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>
LABEL description="postgres with environment variable driven user and database creation"

ENV SERVICE_25_CHECK_SCRIPT nc -vzw1 $SERVICE_IP $SERVICE_PORT || exit 2
ENV SERVICE_25_CHECK_INTERVAL 15s

ADD add-users-and-dbs.sh /docker-entrypoint-initdb.d/
