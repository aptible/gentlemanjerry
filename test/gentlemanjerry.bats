#!/usr/bin/env bats

generate_certs() {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -subj /CN=localhost/ -keyout /tmp/certs/jerry.key -out /tmp/certs/jerry.crt
}

wait_for_gentlemanjerry() {
  # run the gentlemanjerry startup script in the background, then tail its
  # output until we see a single line of output or 120 seconds have elapsed.
  # When either condition is met, we kill the logstash process and test the
  # output against what we expect.
  jerry_log_file="/tmp/logs/jerry.logs"
  rm -f "$jerry_log_file"

  /bin/bash run-gentleman-jerry.sh 2>&1 > "$jerry_log_file" &

  for i in $(seq 1 10); do
    if grep -q "fluentd worker is now running" "$jerry_log_file"; then
      return 0
    fi
    sleep 1
  done

  echo "Gentlemanjerry did not start in time, or failed to start:"
  echo "$(cat $jerry_log_file)"
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
  export FLUENTD_MONITOR_CONFIG='@type stdout'
  mkdir /tmp/certs
  mkdir /tmp/logs
}

teardown() {
  # Here again, we kill everything with SIGKILL, to ensure that nothing stays
  # up between tests / takes a little while to exit.
  pkill -KILL -f run-gentleman-jerry
  pkill -KILL -f 'fluentd'
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

@test "Gentleman Jerry should not start up with a default configuration" {
  generate_certs
  run timeout 10 /bin/bash run-gentleman-jerry.sh

  [[ "$output" =~ "Missing '@type' parameter on <match> directive" ]]
}

@test "Gentleman Jerry should allow certificates in the environment" {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -subj /CN=Example/ -keyout jerry.key -out jerry.crt
  # First, generate a valid config
  export FLUENTD_OUTPUT_CONFIG="@type http
                                endpoint 127.0.0.1
                                open_timeout 2
                                <format>
                                  @type json
                                </format>
                                <buffer>
                                  flush_interval 5s
                                </buffer>"
  SSL_CERTIFICATE="$(cat jerry.crt)" SSL_KEY="$(cat jerry.key)" wait_for_gentlemanjerry
  rm jerry.key jerry.crt
}

@test "Gentleman Jerry should start up with a syslog output configuration" {
  generate_certs
  export FLUENTD_OUTPUT_CONFIG="@type syslog_rfc5424
                                host 127.0.0.1
                                port 514
                                <format>
                                  @type syslog_rfc5424
                                  app_name_field service
                                  log_field message
                                </format>
                                <buffer>
                                  flush_interval 5s
                                </buffer>"
  wait_for_gentlemanjerry
}

@test "Gentleman Jerry should restart if it dies" {
  generate_certs
  export FLUENTD_OUTPUT_CONFIG="@type http
                                endpoint 127.0.0.1
                                open_timeout 2
                                <format>
                                  @type json
                                </format>
                                <buffer>
                                  flush_interval 5s
                                </buffer>"
  wait_for_gentlemanjerry
  # Force an unclean shutdown to avoid GentlemanJerry exiting with 0
  pkill -KILL -f 'fluentd'
  timeout 10 grep -q "GentlemanJerry died, restarting..." <(tail -f /tmp/logs/jerry.logs)
  pkill -f 'tail' || true
  run timeout 10 grep -q "fluentd worker is now running" <(tail -f /tmp/logs/jerry.logs)
  pkill -f 'tail' || true
  pkill -f run-gentleman-jerry
  pkill -f 'fluentd'
  [ "$status" -eq 0 ]  # Command should have finished before timeout. We'd get 143 if it timed out.
}
