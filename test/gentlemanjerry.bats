#!/usr/bin/env bats

generate_certs() {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -keyout /tmp/certs/jerry.key -out /tmp/certs/jerry.crt
}

wait_for_gentlemanjerry() {
  # Unfortunately, it takes a while for logstash to start up. The tests below
  # run the gentlemanjerry startup script in the background, then tail its
  # output until we see a single line of output or 120 seconds have elapsed.
  # When either condition is met, we kill the logstash process and test the
  # output against what we expect.
  jerry_log_file="/tmp/logs/jerry.logs"

  /bin/bash run-gentleman-jerry.sh 2>&1 > "$jerry_log_file" &

  for i in $(seq 1 120); do
    if grep -q "Logstash startup completed" "$jerry_log_file"; then
      return 0
    fi
    sleep 1
  done

  echo "Gentlemanjerry did not start in time, or failed to start:"
  cat "$jerry_log_file"
  return 1
}

setup() {
  mkdir /tmp/certs
  mkdir /tmp/logs
}

teardown() {
  # Here again, we kill everything with SIGKILL, to ensure that nothing stays
  # up between tests / takes a little while to exit.
  pkill -KILL -f run-gentleman-jerry
  pkill -KILL -f 'java.*logstash'
  pkill -KILL redis-server || true
  pkill -KILL stunnel || true

  rm -rf /tmp/certs
  rm -rf /tmp/logs
}

@test "Gentleman Jerry reports an error if its certificate isn't in /tmp/certs" {
  touch /tmp/certs/jerry.key
  run /bin/bash run-gentleman-jerry.sh
  [ "$status" -eq 1 ]
  [[ "$output" =~ "/tmp/certs/jerry.crt" ]]
}

@test "Gentleman Jerry reports an error if its private key isn't in /tmp/certs" {
  touch /tmp/certs/jerry.crt
  run /bin/bash run-gentleman-jerry.sh
  [ "$status" -eq 1 ]
  [[ "$output" =~ "/tmp/certs/jerry.key" ]]
}

@test "Gentleman Jerry should start up with a default configuration" {
  generate_certs
  wait_for_gentlemanjerry
}

@test "Gentleman Jerry should start up with a syslog output configuration" {
  generate_certs
  export LOGSTASH_OUTPUT_CONFIG="syslog { facility => \"daemon\" host => \"127.0.0.1\" port => 514 severity => \"emergency\" }"
  wait_for_gentlemanjerry
}

@test "Gentleman Jerry should start up with a Redis pubsub configuration" {
  export REDIS_PASSWORD="foobar123"

  export LOGSTASH_OUTPUT_CONFIG="redis {
    data_type => \"script\"
    key => \"__LOAD_SCRIPT_SHA__\"
    password => \"${REDIS_PASSWORD}\"
  }"

  export LOGSTASH_FILTERS="ruby {
    code => 'event[\"unix_timestamp\"] = event[\"@timestamp\"].to_i'
  }"

  generate_certs
  wait_for_gentlemanjerry

  # Check that stunnel and Redis came online as well
  pgrep stunnel
  pgrep redis-server

  # Check that we can connect over ssl
  run timeout 3 openssl s_client -CAfile "/tmp/certs/jerry.crt" -connect localhost:6000
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]

  # Now, send some traffic into Logstash
  "/logstash-${LOGSTASH_VERSION}/bin/logstash" -f "${BATS_TEST_DIRNAME}/feed-logstash.config"

  # And check if Redis received the message
  found_buffer_map=0
  for _ in $(seq 1 20); do
    echo $(date) >> /search
    echo "Looking for buffer map??"
    redis-cli -a "$REDIS_PASSWORD" KEYS '*' > "/tmp/logs/keys"
    if grep "buffer-map" "/tmp/logs/keys"; then
      found_buffer_map=1
      break
    fi
    sleep 1
  done
  [[ "$found_buffer_map" -eq 1 ]]
}

@test "Gentleman Jerry should restart if it dies" {
  generate_certs
  export LOGSTASH_OUTPUT_CONFIG="syslog { facility => \"daemon\" host => \"127.0.0.1\" port => 514 severity => \"emergency\" }"
  wait_for_gentlemanjerry
  # Force an unclean shutdown to avoid GentlemanJerry exiting with 0
  pkill -KILL -f 'java.*logstash'
  timeout 10 grep -q "GentlemanJerry died, restarting..." <(tail -f /tmp/logs/jerry.logs)
  pkill -f 'tail'
  run timeout 120 grep -q "Logstash startup completed" <(tail -f /tmp/logs/jerry.logs)
  pkill -f 'tail'
  pkill -f run-gentleman-jerry
  pkill -f 'java.*logstash'
  [ "$status" -eq 0 ]  # Command should have finished before timeout. We'd get 143 if it timed out.
}

# We send syslog over TLS to various log drains-as-a-service and need to be able to
# verify their certificate chains with the system certificates we have in
# /usr/lib/ssl/cert.pem. This file is passed to logstash in the SSL_CERT_FILE environment
# variable, which Ruby reads. These next few tests verify that this cert file works.

@test "Gentleman Jerry can verify logs.papertrailapp.com:514's certificate" {
  run timeout 3 openssl s_client -CAfile /etc/ssl/certs/ca-certificates.crt -connect logs.papertrailapp.com:514
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
  run timeout 3 java -cp /tmp/test SslTest logs.papertrailapp.com 514
  [ "$status" -eq 0 ]
}

@test "Gentleman Jerry can verify api.logentries.com:25414's certificate" {
  run timeout 3 openssl s_client -CAfile /etc/ssl/certs/ca-certificates.crt -connect api.logentries.com:25414
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
  run timeout 3 java -cp /tmp/test SslTest api.logentries.com 25414
  [ "$status" -eq 0 ]
}
