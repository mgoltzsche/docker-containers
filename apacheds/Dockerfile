FROM algorythm/consul-service-openjdk:8
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV APACHEDS_VERSION 2.0.0-M21
ENV LDAP_DOMAIN algorythm.de

RUN addgroup apacheds && \
	adduser -S -G apacheds apacheds
RUN cd /tmp && \
	wget -O apacheds.tar.gz http://apache.openmirror.de/directory/apacheds/dist/$APACHEDS_VERSION/apacheds-$APACHEDS_VERSION.tar.gz && \
	tar -xzf apacheds.tar.gz && \
	mv apacheds-$APACHEDS_VERSION /apacheds && \
	mkdir /apacheds/ldif && \
	mv /apacheds/instances/default/conf/config.ldif /apacheds/ldif/default-config.ldif && \
	chown -R apacheds:apacheds /apacheds && \
	echo -n 'secret' > /etc/apachedspw && \
	chmod 400 /etc/apachedspw && \
	rm apacheds.tar.gz && \
	rm /apacheds/bin/*.bat
ADD config/reset-admin-password.sh /apacheds/bin/
ADD config/setup-instance.sh /apacheds/bin/
ADD config/consul-apacheds-service.json /consul/config/local/apacheds.json
ADD config/algorythm-backup.ldif /apacheds/ldif/
ADD entrypoint.sh /entrypoint-apacheds.sh
RUN chmod 544 /entrypoint-apacheds.sh && \
	chmod 700 /apacheds/bin/reset-admin-password.sh && \
	chmod 544 /apacheds/bin/setup-instance.sh && \
	chmod 444 /consul/config/local/apacheds.json
RUN apk add --no-cache --update openldap-clients
RUN /apacheds/bin/setup-instance.sh $LDAP_DOMAIN
EXPOSE 10389 10636

ENTRYPOINT ["/entrypoint-apacheds.sh"]
CMD ["run"]
