FROM fluent/fluentd:v1.12.1-1.0

USER root

# Add extra certificates. Specifically, rapidssl is needed because it's used
# by Papertrail.
ENV LOCAL_TRUST_DIR /usr/local/share/ca-certificates
COPY rapidssl.crt "$LOCAL_TRUST_DIR/rapidssl.crt"
RUN update-ca-certificates

# The Redis output is used with a local Redis, so we need to install it. We
# also pull coreutils, largely for convenience in our tests.
RUN apk add --no-cache coreutils curl bash openssl

# Install the necessary plugins
RUN apk add --no-cache --update --virtual .build-deps \
      build-base ruby-dev git \
      && git clone -b aptible https://github.com/almathew/fluent-plugin-logdna.git \
      && cd fluent-plugin-logdna \
      && gem build fluent-plugin-logdna.gemspec \
      && gem install fluent-plugin-logdna-0.4.0.gem \
      && cd .. \
      && git clone https://github.com/aptible/fluent-plugin-out-http.git \
      && cd fluent-plugin-out-http \
      && gem build fluent-plugin-out-http.gemspec \
      && gem install fluent-plugin-out-http-1.3.3.gem \
      && cd .. \
      && git clone -b auth-options https://github.com/aptible/fluent-plugin-influxdb.git \
      && cd fluent-plugin-influxdb \
      && gem build fluent-plugin-influxdb.gemspec \
      && gem install fluent-plugin-influxdb-2.0.0.gem \
      && cd .. \
      && gem sources --clear-all \
      && apk del .build-deps \
      && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

RUN gem install fluent-plugin-papertrail
RUN gem install fluent-plugin-sumologic_output
RUN gem install fluent-plugin-beats --no-document
RUN gem install fluent-plugin-syslog_rfc5424
RUN gem install fluent-plugin-datadog
RUN gem install elasticsearch -v 7.13.3
RUN gem install fluent-plugin-elasticsearch -v 5.0.4

COPY templates/fluent.conf.erb /fluent.conf.erb
COPY bin/run-gentleman-jerry.sh run-gentleman-jerry.sh

# Install BATS (for tests)
RUN curl -sL https://github.com/sstephenson/bats/archive/master.zip > /tmp/bats.zip \
    && cd /tmp \
    && unzip -q bats.zip \
    && ./bats-master/install.sh /usr/local \
    # /usr/local/bin/bats should be a symlink, so make it happen.
    && ln -sf /usr/local/libexec/bats /usr/local/bin/bats \
    && rm -rf /tmp/bats*

# Run tests
COPY test /tmp/test
RUN /tmp/test/run_tests.sh

# A volume containing a certificate pair named jerry.key/jerry.crt must be mounted into
# this directory on the container.
VOLUME ["/tmp/certs"]

# Lumberjack
EXPOSE 5000

CMD ["/bin/bash", "run-gentleman-jerry.sh"]
