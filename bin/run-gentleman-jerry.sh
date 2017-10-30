#!/bin/bash
set -o errexit

SSL_CERTIFICATE_FILE="/tmp/certs/jerry.crt"

if [[ -n "$SSL_CERTIFICATE" ]]; then
  mkdir -p "$(dirname "$SSL_CERTIFICATE_FILE")"
  touch "$SSL_CERTIFICATE_FILE"
  chmod 644 "$SSL_CERTIFICATE_FILE"
  echo "$SSL_CERTIFICATE" > "$SSL_CERTIFICATE_FILE"
  unset SSL_CERTIFICATE
elif [[ ! -f "$SSL_CERTIFICATE_FILE" ]]; then
  echo "Expected certificate in ${SSL_CERTIFICATE_FILE}." >&2
  exit 1
fi

SSL_KEY_FILE="/tmp/certs/jerry.key"

if [[ -n "$SSL_KEY" ]]; then
  mkdir -p "$(dirname "$SSL_KEY_FILE")"
  touch "$SSL_KEY_FILE"
  chmod 600 "$SSL_KEY_FILE"
  echo "$SSL_KEY" > "$SSL_KEY_FILE"
  unset SSL_KEY
elif [[ ! -f "$SSL_KEY_FILE" ]]; then
  echo "Expected certificate in ${SSL_KEY_FILE}." >&2
  exit 1
fi

if [[ -n "$REDIS_PASSWORD" ]]; then
  echo "Generating Redis configuration"
  erb redis.conf.erb > /redis.conf

  echo "Starting stunnel (SSL reverse proxy)"
  stunnel /stunnel.conf &

  echo "Starting Redis"
  redis-server /redis.conf &

  # Now, load the script
  echo "Loading script"
  until LOAD_SCRIPT_SHA="$(redis-cli -a "$REDIS_PASSWORD" SCRIPT LOAD "$(cat "/load-message.lua")")"; do
    echo "Redis is not up yet... Retrying in 1s"
    sleep 1
  done
  export LOAD_SCRIPT_SHA
fi

echo "Generating Logstash configuration"
erb logstash.config.erb > "logstash-${LOGSTASH_VERSION}/logstash.config"

# LS_HEAP_SIZE sets the jvm Xmx argument when running logstash, which restricts
# the max heap size. We set this to 64MB below unless it's overridden by
# GentlemanJerry's LOGSTASH_MAX_HEAP_SIZE. We should be conservative with the
# heap the GentlemanJerry uses since we have one running per Log Drain and on
# shared instances we may have many accounts on the same machine.
export LS_HEAP_SIZE=${LOGSTASH_MAX_HEAP_SIZE:-64M}

# The current logstash-output-elasticsearch plugin floods the console logs with
# INFO-level logs from org.apache.http.* about HTTP retries. These log messages
# don't seem to indicate an actual error, so we're suppressing them here with a
# custom log4j.properties configuration.
export LS_JAVA_OPTS="-Dlog4j.configuration=file:/log4j.properties"

# And finally, we configure Java to log GC work. This makes it easier to
# identify whether Logstash is doing some meaningful work or spending all its
# CPU time in GC.
export LS_JAVA_OPTS="${LS_JAVA_OPTS} -XX:+PrintGC"

cd "logstash-${LOGSTASH_VERSION}"
while true; do
    # Ignore errors to ensure we stay up
    bin/logstash -f logstash.config || true
    sleep 1
    echo "GentlemanJerry died, restarting..."
done
