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

@test "Gentleman Jerry should start up with a default configuration" {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -keyout /tmp/certs/jerry.key -out /tmp/certs/jerry.crt

  # Unfortunately, it takes a while for logstash to start up. The tests below
  # run the gentlemanjerry startup script in the background, then tail its
  # output until we see a single line of output or 120 seconds have elapsed.
  # When either condition is met, we kill the logstash process and test the
  # output against what we expect.

  /bin/bash run-gentleman-jerry.sh > /tmp/logs/jerry.logs &
  run timeout 120 sh -c 'tail --pid=$$ -f /tmp/logs/jerry.logs | { sed "1 q" && kill $$ ;}'
  pkill -f 'java.*logstash'
  [ "$status" -eq 143 ]  # Command should have been terminated. We'd get 124 if it timed out.
  [[ "$output" =~ "Using milestone 1 input plugin 'lumberjack'" ]]
}

@test "Gentleman Jerry should start up with a syslog output configuration" {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -keyout /tmp/certs/jerry.key -out /tmp/certs/jerry.crt
  export LOGSTASH_OUTPUT_CONFIG="syslog { facility => \"daemon\" host => \"127.0.0.1\" port => 514 severity => \"emergency\" }"

  # Unfortunately, it takes a while for logstash to start up. The tests below
  # run the gentlemanjerry startup script in the background, then tail its
  # output until we see two lines of output or 120 seconds have elapsed. When
  # either condition is met, we kill the logstash process and test the output
  # against what we expect.

  /bin/bash run-gentleman-jerry.sh > /tmp/logs/jerry.logs &
  run timeout 120 sh -c 'tail --pid=$$ -f /tmp/logs/jerry.logs | { sed "2 q" && kill $$ ;}'
  pkill -f 'java.*logstash'
  [ "$status" -eq 143 ]  # Command should have been terminated. We'd get 124 if it timed out.
  [[ "$output" =~ "Using milestone 1 input plugin 'lumberjack'" ]]
  [[ "$output" =~ "Using milestone 1 output plugin 'syslog'" ]]
}
