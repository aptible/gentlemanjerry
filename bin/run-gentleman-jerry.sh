#!/bin/bash
if [ ! -f /tmp/certs/jerry.crt ]; then
  echo "Expected certificate in /tmp/certs/jerry.crt."
  exit 1
fi
if [ ! -f /tmp/certs/jerry.key ]; then
  echo "Expected key in /tmp/certs/jerry.key."
  exit 1
fi
if [ ! -f /usr/lib/ssl/cert.pem ]; then
  echo "Expected root CA certificates in /usr/lib/ssl/cert.pem."
  exit 1
fi
erb logstash.config.erb > logstash-1.4.2/logstash.config && \

# SSL_CERT_FILE tells Ruby's OpenSSL library to use our custom CA roots (Which
# is Mozilla's canonical set) to verify syslog TLS servers.
export SSL_CERT_FILE=/usr/lib/ssl/cert.pem

# LS_HEAP_SIZE sets the jvm Xmx argument when running logstash, which restricts
# the max heap size. We set this to 64MB below unless it's overridden by
# GentlemanJerry's LOGSTASH_HEAP_SIZE. We should be conservative with the heap
# the GentlemanJerry uses since we have one running per account and on shared
# instances we may have many accounts on the same machine.
export LS_HEAP_SIZE=${LOGSTASH_MAX_HEAP_SIZE:-64M}

cd logstash-1.4.2 && bin/logstash -f logstash.config
