FROM ruby:2.3.0-alpine
MAINTAINER "Max Goltzsche" <max.goltzsche@algorythm.de>

# Create redmine user and group
RUN addgroup redmine && adduser -S -G redmine redmine

# Add required libraries
RUN apk add --no-cache --update libstdc++ libxml2 libxslt zlib imagemagick sqlite-libs libpq sqlite postgresql-client git

# Add gosu for easy step-down from root
# and tini for signal processing (graceful container termination) and zombie killing
# (Install all in one RUN block to keep image small without build utils)
ENV GOSU_VERSION 1.7
ENV TINI_VERSION v0.9.0
RUN set -x \
	&& apk add --no-cache --update gnupg \
	&& curl -fSL -o /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64" \
	&& curl -fSL -o /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true \
	\
	&& curl -fSL -o /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static" \
	&& curl -fSL -o /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-static.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 6380DC428747F6C393FEACA59A84159D7001A4E5 \
	&& gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini \
	&& rm -r "$GNUPGHOME" /usr/local/bin/tini.asc \
	&& chmod +x /usr/local/bin/tini \
	&& tini -h \
	&& apk del --purge gnupg

# Download and extract Redmine
# Redmine 2.5.2 is the version running on algorythm.de. In docker container has same bug as 2.3.0
# Redmine 2.6.9 is last version installable with Backlogs 1.0.6 because it requires nokogiri < 1.6.0 but Redmine 2.6.10 requires newer version. Backlog task board tasks can be created only if the workflow for the Task tracker is configured properly.
# Redmine 2.3.0 also has the bug not beeing able to create tasks and has ActionView::Template::Error "undefined method name for nil:NilClass" on project creation. 2.5.2 also
ENV REDMINE_VERSION 2.6.9
ENV RAILS_ENV production
ENV REDMINE_LANG en
RUN set -x \
	&& curl -fSL -o "redmine-${REDMINE_VERSION}.tar.gz" "http://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz" \
	&& curl -fSL "http://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz.md5" | md5sum -c - \
	&& tar -xzf "redmine-${REDMINE_VERSION}.tar.gz" \
	&& mv redmine-${REDMINE_VERSION} /redmine \
	&& rm "redmine-${REDMINE_VERSION}.tar.gz" /redmine/files/delete.me /redmine/log/delete.me \
	&& mkdir -p /redmine/tmp/pdf /redmine/public/plugin_assets

# Download and extract Redmine Backlogs plugin
ENV REDMINE_BACKLOGS_VERSION 1.0.6
RUN set -x \
	&& curl -fSL -o redmine-backlogs-plugin.tar.gz "https://github.com/backlogs/redmine_backlogs/archive/v$REDMINE_BACKLOGS_VERSION.tar.gz" \
	&& tar -xzf redmine-backlogs-plugin.tar.gz \
	&& mv redmine_backlogs-$REDMINE_BACKLOGS_VERSION /redmine/plugins/redmine_backlogs \
	&& rm redmine-backlogs-plugin.tar.gz \
	&& chown -R redmine:redmine /redmine

# Install
WORKDIR /redmine
RUN NOKOGIRI_VERSION=$(cat /redmine/Gemfile /redmine/plugins/*/Gemfile 2>/dev/null | grep 'gem "nokogiri"' | grep -Eo '([<=>]+ ?)?[0-9\.]+' | sort | head -n1) \
	BUILD_DEPS='\
		gcc \
		make \
		patch \
		build-base \
		libxml2-dev \
		libxslt-dev \
		imagemagick-dev \
		postgresql-dev \
		sqlite-dev \
	' \
	&& apk add --no-cache --update $BUILD_DEPS \
	&& set -ex \
	&& gem install nokogiri -v "$NOKOGIRI_VERSION" -- --use-system-libraries \
	&& bundle install --without development test \
	&& for adapter in postgresql sqlite3; do \
		echo "$RAILS_ENV:" > ./config/database.yml; \
		echo "  adapter: $adapter" >> ./config/database.yml; \
		bundle install --without development test; \
	done \
	&& rm ./config/database.yml \
	&& apk del --purge $BUILD_DEPS \
	&& chown -R redmine:redmine /redmine

VOLUME /redmine/files
EXPOSE 3000

ADD entrypoint.sh /
RUN chmod 544 /entrypoint.sh

ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
CMD ["thin", "start"]
