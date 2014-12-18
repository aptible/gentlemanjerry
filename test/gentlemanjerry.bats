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
  pkill -f run-gentleman-jerry
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
  pkill -f run-gentleman-jerry
  pkill -f 'java.*logstash'
  [ "$status" -eq 143 ]  # Command should have been terminated. We'd get 124 if it timed out.
  [[ "$output" =~ "Using milestone 1 input plugin 'lumberjack'" ]]
  [[ "$output" =~ "Using milestone 1 output plugin 'syslog'" ]]
}

@test "Gentleman Jerry should restart if it dies" {
  openssl req -x509 -batch -nodes -newkey rsa:2048 -keyout /tmp/certs/jerry.key -out /tmp/certs/jerry.crt
  export LOGSTASH_OUTPUT_CONFIG="syslog { facility => \"daemon\" host => \"127.0.0.1\" port => 514 severity => \"emergency\" }"

  # Unfortunately, it takes a while for logstash to start up. The tests below
  # run the gentlemanjerry startup script in the background, then tail its
  # output until we see two lines of output or 120 seconds have elapsed. At that
  # point, if we haven't timed out, GentlemanJerry has started. We then kill
  # the logstash process and wait for GentlemanJerry to restart, which should
  # create 5 lines in the log (2 for the first startup, 1 to report the restart,
  # then 2 more for the final startup).

  /bin/bash run-gentleman-jerry.sh > /tmp/logs/jerry.logs &
  export JERRYPID=$$
  timeout 120 sh -c 'tail --pid=$JERRYPID -f /tmp/logs/jerry.logs | { sed "2 q" && kill $$ ;}' || [ $? == 143 ]
  pkill -f 'java.*logstash'
  timeout 120 sh -c 'tail --pid=$JERRYPID -f /tmp/logs/jerry.logs | { sed "5 q" && kill $$ ;}' || [ $? == 143 ]
  pkill -f run-gentleman-jerry
  pkill -f 'java.*logstash'
  run cat /tmp/logs/jerry.logs

  [[ "${lines[0]}" =~ "Using milestone 1 input plugin 'lumberjack'" ]]
  [[ "${lines[1]}" =~ "Using milestone 1 output plugin 'syslog'" ]]
  [ "${lines[2]}" = "GentlemanJerry died, restarting..." ]
  [[ "${lines[3]}" =~ "Using milestone 1 input plugin 'lumberjack'" ]]
  [[ "${lines[4]}" =~ "Using milestone 1 output plugin 'syslog'" ]]
}

# We send syslog over TLS to various log drains-as-a-service and need to be able to
# verify their certificate chains with the system certificates we have in
# /usr/lib/ssl/cert.pem. This file is passed to logstash in the SSL_CERT_FILE environment
# variable, which Ruby reads. These next few tests verify that this cert file works.

@test "Gentleman Jerry can verify logs.papertrailapp.com:514's certificate" {
  run timeout 3 openssl s_client -CAfile /usr/lib/ssl/cert.pem -connect logs.papertrailapp.com:514
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
}

@test "Gentleman Jerry can verify logs2.papertrailapp.com:514's certificate" {
  run timeout 3 openssl s_client -CAfile /usr/lib/ssl/cert.pem -connect logs.papertrailapp.com:514
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
}

@test "Gentleman Jerry can verify api.logentries.com:25414's certificate" {
  run timeout 3 openssl s_client -CAfile /usr/lib/ssl/cert.pem -connect api.logentries.com:25414
  [[ "$output" =~ "Verify return code: 0 (ok)" ]]
}
