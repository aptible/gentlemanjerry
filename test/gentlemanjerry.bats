#!/usr/bin/env bats

generate_certs() {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -subj /CN=localhost/ -keyout /tmp/certs/jerry.key -out /tmp/certs/jerry.crt
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

wait_for_tls12_server() {
  openssl_log_file="/tmp/logs/openssl.logs"

  generate_certs

  # Manticore actually supports TLSv1.2, but does not support all cipher suites
  # under TLSv1.2 In particular, it appears to support only the following:
  # AES256-SHA, DHE-RSA-AES256-SHA, DHE-DSS-AES256-SHA, AES128-SHA,
  # DHE-RSA-AES128-SHA, DHE-DSS-AES128-SHA, DES-CBC3-SHA, EDH-RSA-DES-CBC3-SHA,
  # EDH-DSS-DES-CBC3-SHA
  # Unfortunately, none of these are supported by AWS ALB using the TLSv1.2
  # security policy (TLS-1-2-2017-01): http://amzn.to/2FiIswH
  # So, to test whether Manticore can connect to a (presumably common) ALB
  # TLSv1.2 protocol/cipher config, we allow only AES256-SHA256 server-side.
  openssl s_server -cipher AES256-SHA256 -tls1_2 -key /tmp/certs/jerry.key -cert /tmp/certs/jerry.crt -www 2>&1 > "$openssl_log_file" &

  for i in $(seq 1 10); do
    if grep -q "ACCEPT" "$openssl_log_file"; then
      return 0
    fi
    sleep 1
  done

  echo "openssl s_server did not start in time, or failed to start:"
  cat "$openssl_log_file"
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
  pkill -KILL openssl || true

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

@test "Gentleman Jerry should allow certificates in the environment" {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -subj /CN=Example/ -keyout jerry.key -out jerry.crt
  SSL_CERTIFICATE="$(cat jerry.crt)" SSL_KEY="$(cat jerry.key)" wait_for_gentlemanjerry
  rm jerry.key jerry.crt
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
  pkill -f 'tail' || true
  run timeout 120 grep -q "Logstash startup completed" <(tail -f /tmp/logs/jerry.logs)
  pkill -f 'tail' || true
  pkill -f run-gentleman-jerry
  pkill -f 'java.*logstash'
  [ "$status" -eq 0 ]  # Command should have finished before timeout. We'd get 143 if it timed out.
}

# We send syslog over TLS to various log drains-as-a-service and need to be able to
# verify their certificate chains with the system certificates we have in
# /usr/lib/ssl/cert.pem. This file is passed to logstash in the SSL_CERT_FILE environment
# variable, which Ruby reads. These next few tests verify that this cert file works.

@test "Gentleman Jerry can verify logs.papertrailapp.com:514's certificate" {
  run timeout 10 openssl s_client -CAfile /etc/ssl/certs/ca-certificates.crt -connect logs.papertrailapp.com:514
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
  run timeout 10 java -cp /tmp/test SslTest logs.papertrailapp.com 514
  [ "$status" -eq 0 ]
}

@test "Gentleman Jerry can verify api.logentries.com:25414's certificate" {
  run timeout 10 openssl s_client -CAfile /etc/ssl/certs/ca-certificates.crt -connect api.logentries.com:25414
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
  run timeout 10 java -cp /tmp/test SslTest api.logentries.com 25414
  [ "$status" -eq 0 ]
}

@test "Gentleman Jerry can connect to a TLSv1.2-only Endpoint" {
  wait_for_tls12_server
  timeout 5 openssl s_client -CAfile /tmp/certs/jerry.crt -connect localhost:4433 | grep "Verify return code: 0 (ok)"

  # Import cert into test truststore
  keytool -importcert -file /tmp/certs/jerry.crt -keystore /tmp/certs/jerry.jks -storepass testpass -noprompt

  # Set up JRuby and its gems
  export PATH="/logstash-$LOGSTASH_VERSION/vendor/jruby/bin:$PATH"
  export GEM_PATH="/logstash-$LOGSTASH_VERSION/vendor/bundle/jruby/1.9"

  jruby /tmp/test/manticore_test.rb https://localhost:4433 /tmp/certs/jerry.jks
}

@test "Gentleman Jerry can connect to a TLSv1.2-only Endpoint (variant)" {
  # Set up JRuby and its gems
  export PATH="/logstash-$LOGSTASH_VERSION/vendor/jruby/bin:$PATH"
  export GEM_PATH="/logstash-$LOGSTASH_VERSION/vendor/bundle/jruby/1.9"

  jruby /tmp/test/manticore_test.rb https://tlsv12-elb.aptible-test-grumpycat.com
}
