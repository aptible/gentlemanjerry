#!/bin/bash
set -o errexit

SSL_CERTIFICATE_FILE="/tmp/certs/jerry.crt"

if [[ -n "$SSL_CERTIFICATE" ]]; then
  mkdir -p "$(dirname "$SSL_CERTIFICATE_FILE")"
  touch "$SSL_CERTIFICATE_FILE"
  chmod 644 "$SSL_CERTIFICATE_FILE"
  echo "$SSL_CERTIFICATE" >"$SSL_CERTIFICATE_FILE"
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
  echo "$SSL_KEY" >"$SSL_KEY_FILE"
  unset SSL_KEY
elif [[ ! -f "$SSL_KEY_FILE" ]]; then
  echo "Expected certificate in ${SSL_KEY_FILE}." >&2
  exit 1
fi

if [[ -n "$REDIS_PASSWORD" ]]; then
  echo "Generating Redis configuration"
  erb redis.conf.erb >/redis.conf

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

echo "Generating Fluentd configuration"
erb fluent.conf.erb >/fluentd/etc/fluent.conf

while true; do
  # Ignore errors to ensure we stay up
  /usr/bin/fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins || true
  sleep 1
  echo "GentlemanJerry died, restarting..."
done
