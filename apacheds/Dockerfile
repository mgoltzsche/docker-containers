FROM algorythm/consul-service-openjdk:8
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV APACHEDS_VERSION 2.0.0-M21
ENV DOMAIN algorythm.de

RUN addgroup apacheds && \
	adduser -S -G apacheds apacheds
RUN cd /tmp && \
	wget -O apacheds.tar.gz http://apache.openmirror.de/directory/apacheds/dist/$APACHEDS_VERSION/apacheds-$APACHEDS_VERSION.tar.gz && \
	tar -xzf apacheds.tar.gz && \
	mv apacheds-$APACHEDS_VERSION /apacheds && \
	mkdir /apacheds/ldif && \
	mv /apacheds/instances/default/conf/config.ldif /apacheds/ldif/default-config.ldif && \
	chown -R apacheds:apacheds /apacheds && \
	rm apacheds.tar.gz && \
	rm /apacheds/bin/*.bat
ADD config/setup-instance.sh /apacheds/bin/
#ADD config/setup-partition.ldif /apacheds/ldif/
#ADD config/delete-example.ldif /apacheds/ldif/
ADD entrypoint.sh /apacheds.sh
RUN chmod 544 /apacheds.sh && \
	chmod 544 /apacheds/bin/setup-instance.sh
RUN /apacheds/bin/setup-instance.sh $DOMAIN
RUN apk add --update openldap-clients
EXPOSE 10389 10636

ENTRYPOINT ["/apacheds.sh"]
CMD ["run"]
