FROM quay.io/aptible/alpine

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

# Download the logstash tarball, verify its SHA against a golden SHA, extract it.
RUN curl -O https://download.elastic.co/logstash/logstash/logstash-1.5.1.tar.gz && \
    echo "526bf554d1f1e27354f3816c1a3576a83ac1ca05  logstash-1.5.1.tar.gz" | sha1sum -c - && \
    tar zxf logstash-1.5.1.tar.gz

# Install our syslog output implementation
RUN apk-install git && \
    echo "gem 'logstash-output-syslog', :git => 'https://github.com/aaw/logstash-output-syslog'," \
         ":branch => 'aptible'" >> /logstash-1.5.1/Gemfile && \
    /logstash-1.5.1/bin/plugin install --no-verify && \
    apk del git

# The logstash-output-elasticsearch plugin needs log4j-1.2.17.jar added to its
# runtime dependencies so that we can suppress some of the Java logging. This
# jar already exists in the dependencies for some other plugins, so we just copy
# from one of them.
RUN cp /logstash-1.5.1/vendor/bundle/jruby/1.9/gems/*/vendor/jar-dependencies/runtime-jars/log4j-1.2.17.jar \
       /logstash-1.5.1/vendor/bundle/jruby/1.9/gems/logstash-output-elasticsearch*/vendor/jar-dependencies/runtime-jars/

ADD templates/logstash.config.erb /logstash.config.erb
ADD templates/log4j.properties /log4j.properties
ADD bin/run-gentleman-jerry.sh run-gentleman-jerry.sh

# Run tests
ADD test /tmp/test
RUN /tmp/test/run_tests.sh

# A volume containing a certificate pair named jerry.key/jerry.crt must be mounted into
# this directory on the container.
VOLUME ["/tmp/certs"]

CMD ["/bin/bash", "run-gentleman-jerry.sh"]
