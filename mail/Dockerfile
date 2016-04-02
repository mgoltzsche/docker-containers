FROM algorythm/consul:latest
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV DOMAIN algorythm.de
ENV LDAP_SUFFIX dc=algorythm,dc=de

# Add user
RUN addgroup -g 5000 vmail && \
    adduser -u 5000 -S -G vmail vmail

# Install postfix & dovecot
RUN apk add --no-cache postfix postfix-ldap dovecot dovecot-ldap

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

# Configure entrypoint
ADD entrypoint.sh /entrypoint-mail.sh
RUN chmod 544 /entrypoint-mail.sh && \
    find /setup -name '*.sh' | xargs chmod u+x
ENTRYPOINT ["/entrypoint-mail.sh"]
CMD ["run"]
