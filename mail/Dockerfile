FROM alpine:3.3
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV DOMAIN algorythm.de
ENV LDAP_SUFFIX dc=algorythm,dc=de
# Health checks registered by registrator container
#ENV SERVICE_25_CHECK_TCP true # supported since consul 0.6
#ENV SERVICE_25_CHECK_INTERVAL 30s
#ENV SERVICE_25_CHECK_TIMEOUT 1s
# see bottom for checks

# Add user
RUN addgroup -g 5000 vmail && \
    adduser -u 5000 -S -G vmail vmail

# Install rsyslog, postfix and dovecot + ldap integration
RUN apk add --no-cache --update rsyslog postfix postfix-ldap dovecot dovecot-ldap

# Install tini for signal processing (graceful container termination) and zombie killing
ENV TINI_VERSION v0.9.0
RUN set -x \
	&& apk add --no-cache --update curl gnupg \
	&& curl -fSL -o /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static" \
	&& curl -fSL -o /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 6380DC428747F6C393FEACA59A84159D7001A4E5 \
	&& gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini \
	&& rm -r "$GNUPGHOME" /usr/local/bin/tini.asc \
	&& chmod +x /usr/local/bin/tini \
	&& tini -h \
	&& apk del --purge curl gnupg

# Enable submission and smpts for postfix
RUN echo $'\n\
submission inet n       -       n       -       -       smtpd\n\
  -o syslog_name=postfix/submission\n\
  -o smtpd_tls_security_level=encrypt\n\
  -o smtpd_sasl_auth_enable=yes\n\
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject\n\
  -o milter_macro_daemon_name=ORIGINATING\n\
smtps     inet  n       -       n       -       -       smtpd\n\
  -o syslog_name=postfix/smtps\n\
  -o smtpd_tls_security_level=encrypt\n\
  -o smtpd_tls_wrappermode=yes\n\
  -o smtpd_sasl_auth_enable=yes\n\
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject\n\
  -o milter_macro_daemon_name=ORIGINATING' \
  >> /etc/postfix/master.cf

# Add vmail directory
RUN mkdir /var/mail && \
    chown -R vmail:vmail /var/mail && \
    chmod 00750 /var/mail

# Expose postfix mail queue volume
VOLUME /var/spool/postfix
# Expose dovecot maildir volume
VOLUME /var/mail

# Postfix ports
EXPOSE 25 465 587
# Dovecot ports
EXPOSE 110 143 993 995

# Add custom configuration
ADD mail-setup.sh /sbin/setup-mail
ADD postfix-main.cf.tpl /etc/postfix/main.cf.tpl
ADD rsyslog.conf /etc/rsyslog.conf
ADD dovecot.conf /etc/dovecot/dovecot.conf

ENV SERVICE_25_CHECK_SCRIPT nc -vzw1 $SERVICE_IP $SERVICE_PORT || exit 2
ENV SERVICE_25_CHECK_INTERVAL 15s
ENV SERVICE_110_CHECK_SCRIPT echo SERVICE $SERVICE_IP $SERVICE_PORT >&2
ENV SERVICE_110_CHECK_INTERVAL 15s

# Configure entrypoint
ADD entrypoint.sh /
RUN chmod 544 /entrypoint.sh /sbin/setup-mail
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["run"]
