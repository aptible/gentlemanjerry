#!/bin/bash
LOGSTASH_VERSION="1.5.0"
if [ ! -f /tmp/certs/jerry.crt ]; then
  echo "Expected certificate in /tmp/certs/jerry.crt."
  exit 1
fi
if [ ! -f /tmp/certs/jerry.key ]; then
  echo "Expected key in /tmp/certs/jerry.key."
  exit 1
fi
erb logstash.config.erb > logstash-${LOGSTASH_VERSION}/logstash.config && \

# LS_HEAP_SIZE sets the jvm Xmx argument when running logstash, which restricts
# the max heap size. We set this to 64MB below unless it's overridden by
# GentlemanJerry's LOGSTASH_HEAP_SIZE. We should be conservative with the heap
# the GentlemanJerry uses since we have one running per account and on shared
# instances we may have many accounts on the same machine.
export LS_HEAP_SIZE=${LOGSTASH_MAX_HEAP_SIZE:-64M}

cd logstash-${LOGSTASH_VERSION}
while true; do
    bin/logstash -f logstash.config
    sleep 1
    echo "GentlemanJerry died, restarting..."
done
