FROM algorythm/consul:latest
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV DOMAIN algorythm.de
ENV LDAP_SUFFIX dc=algorythm,dc=de

# Add user
RUN addgroup -g 5000 vmail && \
    adduser -u 5000 -S -G vmail vmail

# Install rsyslog, postfix and dovecot + ldap integration
RUN apk add --no-cache --update rsyslog postfix postfix-ldap dovecot dovecot-ldap

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

EXPOSE 25

# Add custom configuration
ADD mail-setup.sh /sbin/setup-mail
ADD postfix-main.cf.tpl /etc/postfix/main.cf.tpl
ADD rsyslog.conf /etc/rsyslog.conf
ADD dovecot.conf /etc/dovecot/dovecot.conf
ADD consul-mail-service.json /consul/config/local/mail.json

# Configure entrypoint
ADD entrypoint.sh /entrypoint-mail.sh
RUN chmod 544 /entrypoint-mail.sh /sbin/setup-mail
ENTRYPOINT ["/entrypoint-mail.sh"]
CMD ["run"]
