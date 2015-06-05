FROM quay.io/aptible/alpine

RUN apk update && apk-install curl openjdk7-jre-base ruby

# Download a snapshot of Mozilla's root certificates file and save it to
# /usr/lib/ssl/cert.pem. We need this to validate the certificate chains of
# various off-brand certs used by papertrail, logentries, etc.
RUN curl -O https://papertrailapp.com/tools/papertrail-bundle.pem && \
    echo "ab6a49f7788235bab954500c46e0c4a9c451797c  papertrail-bundle.pem" | sha1sum -c -

# The OpenJDK package comes with an empty cacerts file, so we need to generate
# one from the certificate bundle above so that logstash plugin installation will
# work and TLS-TCP syslog will work without setting an SSL_CERT_FILE environment
# variable. Adding everything from papertrail-bundle.pem to the cacerts file
# involves splitting the bundle into its constituent certificates and importing
# them one-by-one into the generated cacerts file.
RUN mkdir -p /tmp/split-certs && \
    cat papertrail-bundle.pem | \
      awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} {print > "/tmp/split-certs/cert" n ".pem"}' && \
    find /tmp/split-certs/* -exec keytool -import -trustcacerts -storepass changeit -noprompt -file {} -alias {} \
      -keystore /usr/lib/jvm/java-1.7-openjdk/jre/lib/security/cacerts \; && \
    keytool -list -keystore /usr/lib/jvm/java-1.7-openjdk/jre/lib/security/cacerts --storepass changeit

# Download the logstash tarball, verify its SHA against a golden SHA, extract it.
RUN curl -O https://download.elastic.co/logstash/logstash/logstash-1.5.0.tar.gz && \
    echo "9729c2d31fddaabdd3d8e94c34a6d1f61d57f94a  logstash-1.5.0.tar.gz" | sha1sum -c - && \
    tar zxf logstash-1.5.0.tar.gz

# Install our syslog output implementation
RUN apk-install git && \
    echo "gem 'logstash-output-syslog', :git => 'https://github.com/aaw/logstash-output-syslog'," \
         ":branch => 'aptible'" >> /logstash-1.5.0/Gemfile && \
    /logstash-1.5.0/bin/plugin install --no-verify && \
    apk del git

ADD templates/logstash.config.erb /logstash.config.erb
ADD bin/run-gentleman-jerry.sh run-gentleman-jerry.sh

# Run tests
ADD test /tmp/test
RUN bats /tmp/test

# A volume containing a certificate pair named jerry.key/jerry.crt must be mounted into
# this directory on the container.
VOLUME ["/tmp/certs"]

CMD ["/bin/bash", "run-gentleman-jerry.sh"]
