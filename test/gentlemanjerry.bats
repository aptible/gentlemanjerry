#!/usr/bin/env bats

setup() {
  mkdir /tmp/certs
}

teardown() {
  rm -rf /tmp/certs
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
  # Unfortunately, it takes a couple of seconds for logstash to start up. This
  # timeout might need to be increased on slower machines.
  run timeout 15s /bin/bash run-gentleman-jerry.sh
  [ "$status" -eq 124 ]
  [[ "$output" =~ "Using milestone 1 input plugin 'lumberjack'" ]]
}

@test "Gentleman Jerry should start up with a syslog output configuration" {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -keyout /tmp/certs/jerry.key -out /tmp/certs/jerry.crt
  export LOGSTASH_OUTPUT_CONFIG="syslog { facility => \"daemon\" host => \"127.0.0.1\" port => 514 severity => \"emergency\" }"
  # Unfortunately, it takes a couple of seconds for logstash to start up. This
  # timeout might need to be increased on slower machines.
  run timeout 15s /bin/bash run-gentleman-jerry.sh
  [ "$status" -eq 124 ]
  [[ "$output" =~ "Using milestone 1 input plugin 'lumberjack'" ]]
  [[ "$output" =~ "Using milestone 1 output plugin 'syslog'" ]]
}
