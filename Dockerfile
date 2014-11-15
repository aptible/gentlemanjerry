FROM quay.io/aptible/ubuntu:14.04

# Install curl, oracle-java7 and ruby.
RUN apt-get update && \
    apt-get install -y python-software-properties software-properties-common
RUN add-apt-repository ppa:webupd8team/java
RUN echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
RUN echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
RUN apt-get update && \
    apt-get install -y curl oracle-java7-installer ruby && \
    apt-get clean

# Download a snapshot of Mozilla's root certificates file, add it to the system certificates
# at /etc/ssl/certs. We need this to validate the certificate chains of various off-brand
# certs used by papertrail, logentries, etc.
RUN curl -O https://papertrailapp.com/tools/papertrail-bundle.pem && \
    echo "ab6a49f7788235bab954500c46e0c4a9c451797c papertrail-bundle.pem" | sha1sum -c - && \
    mv papertrail-bundle.pem /usr/lib/ssl/cert.pem

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