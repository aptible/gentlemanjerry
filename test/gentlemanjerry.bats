#!/usr/bin/env bats

setup() {
  mkdir /tmp/certs
  mkdir /tmp/logs
}

teardown() {
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

kill_gentlemanjerry() {
  pkill -f run-gentleman-jerry
  pkill -f 'java.*logstash'
}

@test "Gentleman Jerry should start up with a default configuration" {
  generate_certs
  wait_for_gentlemanjerry
  kill_gentlemanjerry
}

@test "Gentleman Jerry should start up with a syslog output configuration" {
  generate_certs
  export LOGSTASH_OUTPUT_CONFIG="syslog { facility => \"daemon\" host => \"127.0.0.1\" port => 514 severity => \"emergency\" }"
  wait_for_gentlemanjerry
  kill_gentlemanjerry
}

@test "Gentleman Jerry should start up with a Redis pubsub configuration" {
  export REDIS_PASSWORD="foobar123"

  export LOGSTASH_OUTPUT_CONFIG="redis {
    data_type => \"script\"
    key => \"__LOAD_SCRIPT_SHA__\"
    password => \"${REDIS_PASSWORD}\"
  }"

  generate_certs
  wait_for_gentlemanjerry

  # Check that stunnel and Redis came online as well
  pgrep stunnel
  pgrep redis-server

  kill_gentlemanjerry
  pkill redis-server
  pkill stunnel
}

@test "Gentleman Jerry should restart if it dies" {
  generate_certs
  export LOGSTASH_OUTPUT_CONFIG="syslog { facility => \"daemon\" host => \"127.0.0.1\" port => 514 severity => \"emergency\" }"
  wait_for_gentlemanjerry
  pkill -f 'java.*logstash'
  run timeout -t 120 grep -q "GentlemanJerry died, restarting..." <(tail -f /tmp/logs/jerry.logs)
  pkill -f 'tail'
  run timeout -t 120 grep -q "Logstash startup completed" <(tail -f /tmp/logs/jerry.logs)
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
  run timeout -t 3 openssl s_client -CAfile /etc/ssl/certs/ca-certificates.crt -connect logs.papertrailapp.com:514
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
  run timeout -t 3 java -cp /tmp/test SslTest logs.papertrailapp.com 514
  [ "$status" -eq 0 ]
}

@test "Gentleman Jerry can verify api.logentries.com:25414's certificate" {
  run timeout -t 3 openssl s_client -CAfile /etc/ssl/certs/ca-certificates.crt -connect api.logentries.com:25414
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
  run timeout -t 3 java -cp /tmp/test SslTest api.logentries.com 25414
  [ "$status" -eq 0 ]
}
