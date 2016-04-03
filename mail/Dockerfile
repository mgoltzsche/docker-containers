FROM algorythm/consul:latest
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV DOMAIN algorythm.de
ENV LDAP_SUFFIX dc=algorythm,dc=de

# Add user
RUN addgroup -g 5000 vmail && \
    adduser -u 5000 -S -G vmail vmail

# Install rsyslog (for postfix), postfix, dovecot and ldap integration
# (mail logging facility configured in /etc/rsyslog.conf per default)
RUN apk add --no-cache --update rsyslog postfix postfix-ldap dovecot dovecot-ldap

# Enable submission and smpts
RUN echo $'\n\
submission inet n       -       n       -       -       smtpd\n\
  -o smtpd_tls_security_level=encrypt\n\
  -o smtpd_sasl_auth_enable=yes\n\
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject\n\
  -o milter_macro_daemon_name=ORIGINATING\n\
smtps     inet  n       -       n       -       -       smtpd\n\
  -o smtpd_tls_security_level=encrypt\n\
  -o smtpd_tls_wrappermode=yes\n\
  -o smtpd_sasl_auth_enable=yes\n\
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject\n\
  -o milter_macro_daemon_name=ORIGINATING' \
  >> /etc/postfix/master.cf

# Add directories
RUN mkdir /var/mail && \
    chown -R vmail:vmail /var/mail && \
    chmod 00750 /var/mail

# Postfix mail queue
VOLUME /var/spool/postfix
# Dovecot maildir
VOLUME /var/mail

#EXPOSE 8300

# Add custom configuration
ADD setup /setup
ADD consul-mail-service.json /consul/config/local/mail.json

# Configure entrypoint
ADD entrypoint.sh /entrypoint-mail.sh
RUN chmod 544 /entrypoint-mail.sh && \
    find /setup -name '*.sh' | xargs chmod u+x
ENTRYPOINT ["/entrypoint-mail.sh"]
CMD ["run"]
