FROM alpine:3.4
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

ENV MAILPILE_VERSION=0.5.2

# PROBLEM: Doesn't support multiple users and has encoding issues
# -> Better use RoundCube and disable Google spellchecking there
# TODO: run as unprivilegded user and expose data volume from user's home
# Download mailpile
RUN set -x \
	&& apk add --no-cache --update openssl \
	&& wget -O mailpile.tar.gz https://github.com/mailpile/Mailpile/archive/$MAILPILE_VERSION.tar.gz \
	&& tar -xzf mailpile.tar.gz \
	&& mv Mailpile-$MAILPILE_VERSION /mailpile \
	&& rm mailpile.tar.gz

WORKDIR /mailpile

# Install mailpile
RUN set -x \
	&& apk add --no-cache --update \
		zlib \
		gnupg1 \
		py-pip \
		py-jinja2 \
		py-libxml2 \
		py-libxslt \
		py-lxml \
		ca-certificates \
	&& pip install -r requirements.txt \
	&& ./mp setup \
	&& apk del --purge py-pip

EXPOSE 33411
CMD ./mp --www=0.0.0.0:33411 --wait
