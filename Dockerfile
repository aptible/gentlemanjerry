FROM quay.io/aptible/ubuntu:14.04

# Install curl, openjdk and ruby.
RUN apt-get update && \
    apt-get install -y curl openjdk-7-jre ruby && \
    apt-get clean

# Download the logstash tarball, verify it's SHA against a golden SHA, extract it.
RUN curl -O https://download.elasticsearch.org/logstash/logstash/logstash-1.4.2.tar.gz && \
    echo "d59ef579c7614c5df9bd69cfdce20ed371f728ff logstash-1.4.2.tar.gz" | sha1sum -c - && \
    tar zxf logstash-1.4.2.tar.gz

# Install the logstash contrib modules (need these for syslog outputs, for example.)
RUN /logstash-1.4.2/bin/plugin install contrib

ADD templates/logstash.config.erb /logstash.config.erb
ADD bin/run-gentleman-jerry.sh run-gentleman-jerry.sh

# Override to run a syslog output on TLS over TCP, currently not available in logstash.
# https://github.com/elasticsearch/logstash-contrib/pull/127 may add this to logstash-contrib.
# Until then, we'll just add the file directly to our installation.
ADD syslog.rb /logstash-1.4.2/lib/logstash/outputs/syslog.rb

# Run tests
ADD test /tmp/test
RUN bats /tmp/test

# A volume containing a certificate pair named jerry.key/jerry.crt must be mounted into
# this directory on the container.
VOLUME ["/tmp/certs"]

CMD ["/bin/bash", "run-gentleman-jerry.sh"]