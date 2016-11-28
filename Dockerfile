FROM quay.io/aptible/alpine:3.3

ENV JDK_VERSION openjdk7
RUN apk update && apk-install curl "${JDK_VERSION}-jre-base" ruby java-cacerts

# Add extra certificates. Specifically, rapidssl is needed because it's used
# by Papertrail.
ENV LOCAL_TRUST_DIR /usr/local/share/ca-certificates
ADD rapidssl.crt "$LOCAL_TRUST_DIR/rapidssl.crt"
RUN update-ca-certificates

# And actually ensure Java uses the system trustore java-cacerts creates
RUN JAVA_TRUSTSTORE=/usr/lib/jvm/java-1.7-openjdk/jre/lib/security/cacerts \
 && SYSTEM_TRUSTSTORE=/etc/ssl/certs/java/cacerts \
 && rm "$JAVA_TRUSTSTORE" \
 && ln -s "$SYSTEM_TRUSTSTORE" "$JAVA_TRUSTSTORE"

ENV LOGSTASH_VERSION 1.5.1

# Download the logstash tarball, verify its SHA against a golden SHA, extract it.
RUN curl -O "https://download.elastic.co/logstash/logstash/logstash-${LOGSTASH_VERSION}.tar.gz" && \
    echo "526bf554d1f1e27354f3816c1a3576a83ac1ca05  logstash-${LOGSTASH_VERSION}.tar.gz" | sha1sum -c - && \
    tar zxf "logstash-${LOGSTASH_VERSION}.tar.gz" && \
    rm "logstash-${LOGSTASH_VERSION}.tar.gz"

# Update http output gem
# Install our syslog output implementation
RUN apk-install git && \
    GEMFILE="/logstash-${LOGSTASH_VERSION}/Gemfile" && \
    grep -v 'logstash-output-http' "$GEMFILE" > "${GEMFILE}.tmp" && \
    mv "${GEMFILE}.tmp" "$GEMFILE" && \
    grep -v 'logstash-output-redis' "$GEMFILE" > "${GEMFILE}.tmp" && \
    mv "${GEMFILE}.tmp" "$GEMFILE" && \
    echo "gem 'logstash-output-http', :git => 'https://github.com/krallin/logstash-output-http'," \
         ":ref => '77de2b1'" >> "$GEMFILE" && \
    echo "gem 'logstash-mixin-http_client', :git => 'https://github.com/krallin/logstash-mixin-http_client'," \
         ":ref => '68fa376'" >> "$GEMFILE" && \
    echo "gem 'logstash-output-syslog', :git => 'https://github.com/aaw/logstash-output-syslog'," \
         ":branch => 'aptible'" >> "$GEMFILE" && \
    echo "gem 'logstash-output-redis', :git => 'https://github.com/krallin/logstash-output-redis'," \
         ":ref => '3fa4b3e'" >> "$GEMFILE" && \
    "/logstash-${LOGSTASH_VERSION}/bin/plugin" install --no-verify && \
    apk del git

# The logstash-output-elasticsearch plugin needs log4j-1.2.17.jar added to its
# runtime dependencies so that we can suppress some of the Java logging. This
# jar already exists in the dependencies for some other plugins, so we just copy
# from one of them.
RUN cp "/logstash-${LOGSTASH_VERSION}/vendor/bundle/jruby/1.9/gems/"*"/vendor/jar-dependencies/runtime-jars/log4j-1.2.17.jar" \
       "/logstash-${LOGSTASH_VERSION}/vendor/bundle/jruby/1.9/gems/logstash-output-elasticsearch"*"/vendor/jar-dependencies/runtime-jars/"

# The Redis output is used with a local Redis, so we need to isntall it. We
# also pull coreutils, largely for convenience in our tests.
RUN apk-install coreutils redis

# Now, we need to install stunnel. It's only in the edge repo, and that package
# often breaks, so we install from source.
ADD bin/install-stunnel.sh install-stunnel.sh
RUN ./install-stunnel.sh

ADD templates/stunnel.conf /stunnel.conf
ADD templates/redis.conf.erb /redis.conf.erb
ADD templates/load-message.lua /load-message.lua
ADD templates/logstash.config.erb /logstash.config.erb
ADD templates/log4j.properties /log4j.properties
ADD bin/run-gentleman-jerry.sh run-gentleman-jerry.sh

# Run tests
ADD test /tmp/test
RUN /tmp/test/run_tests.sh

# A volume containing a certificate pair named jerry.key/jerry.crt must be mounted into
# this directory on the container.
VOLUME ["/tmp/certs"]

# Lumberjack
EXPOSE 5000
# Redis (used if the drain is a tail)
EXPOSE 6000

CMD ["/bin/bash", "run-gentleman-jerry.sh"]
