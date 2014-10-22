#!/bin/bash
if [ ! -f /tmp/certs/jerry.crt ]; then
  echo "Expected certificate in /tmp/certs/jerry.crt."
  exit 1
fi
if [ ! -f /tmp/certs/jerry.key ]; then
  echo "Expected key in /tmp/certs/jerry.key."
  exit 1
fi
erb logstash.config.erb > logstash-1.4.2/logstash.config && \
cd logstash-1.4.2 && \
bin/logstash -f logstash.config
