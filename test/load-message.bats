#!/usr/bin/env bats

function redis-cli() {
  # By default, redis-cli buffers its output, so it doesn't work too well in a
  # pipeline: https://github.com/antirez/redis/issues/2074
  (exec stdbuf -i0 -o0 -e0 redis-cli -a "$REDIS_PASSWORD" "$@")
}

function make_message() {
  local when="$1"
  local what="$2"
  printf '{ "unix_timestamp": %d, "app": "myapp", "log": "%s" }' "$when" "$what"
}

function dump_buffers() {
  local keys="$(redis-cli ZRANGE buffer-map-myapp 0 -1)"
  local n_buffers=0
  for key in $keys; do
    n_buffers=$((n_buffers + 1))
    redis-cli LRANGE "$key" 0 -1 >> "$BUFFER_FILE"
  done
  echo "$n_buffers"
}

function count_unique_messages() {
  local fname="$1"
  local real_count="$(grep -Eo '"redisMessageId":.*\d+' "$fname" | sort | uniq | wc -l)"
  echo "$real_count"
}

function wait_for() {
  for _ in $(seq 1 "$((${WAIT:=2} + 1))" ); do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Command timed out:" "$@"
  return 1
}

setup() {
  export REDIS_PASSWORD="foobar123"
  export TEST_WORK_DIR="/tmp/load-message-tests"
  export BUFFER_FILE="${TEST_WORK_DIR}/buffer.log"
  export STREAM_FILE="${TEST_WORK_DIR}/stream.log"

  mkdir -p "$TEST_WORK_DIR"

  export TEST_CONFIG="${TEST_WORK_DIR}/redis.conf"
  REDIS_ALLOWED_MEMORY='2mb' erb /redis.conf.erb > "$TEST_CONFIG"
  redis-server "$TEST_CONFIG" &
  export REDIS_SERVER_PID=$!

  wait_for redis-cli GET test

  redis-cli SUBSCRIBE "stream-myapp" 2>&1 > "$STREAM_FILE" &
  export REDIS_SUBSCRIBER_PID=$!

  LOAD_SCRIPT_SHA="$(redis-cli SCRIPT LOAD "$(cat "/load-message.lua")")"
  export LOAD_SCRIPT_SHA
}

teardown() {
  # We use SIGKILL here so as to avoid timing issues (i.e. having to wait for those
  # processes to exit cleanly. That's probably fine for now).
  kill -KILL "$REDIS_SUBSCRIBER_PID"
  kill -KILL "$REDIS_SERVER_PID"
  rm -r "$TEST_WORK_DIR"
}

@test "It delivers incoming logs to subscribers" {
  ts="$(date +%s)"
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$ts" "Some message")"
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$ts" "More message")"

  wait_for grep "Some message" "$STREAM_FILE"
  wait_for grep "More message" "$STREAM_FILE"
}

@test "It buffers recent incoming logs" {
  ts="$(date +%s)"
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$ts" "Some message")"

  wait_for grep "Some message" "$STREAM_FILE"

  # Check that we have one buffer, and that the message is in it.
  dump_buffers
  [[ "$(count_unique_messages "$BUFFER_FILE")" -eq 1 ]]
  grep "Some message" "$BUFFER_FILE"
}

@test "It delivers outdated incoming logs to subscribers, but does not buffer them" {
  now="$(date +%s)"
  ts="$((now - 3600))"  # 1 hour old
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$ts" "Some message")"

  wait_for grep "Some message" "$STREAM_FILE"

  # Check that no messages were buffered
  dump_buffers
  [[ "$(count_unique_messages "$BUFFER_FILE")" -eq 0 ]]
  run grep "Some message" "$BUFFER_FILE"
  [[ "$status" -gt 0 ]]
}

@test "It breaks down messages in buffer buckets, and expires them" {
  redis-cli SET "conf-bufferBucketCount" 2
  now="$(date +%s)"

  # Send some that are 2 minutes old (will be evicted)
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$((now - 120))" "Bucket 0 message 1")"
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$((now - 120))" "Bucket 0 message 2")"

  # Send some that are a minute old
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$((now - 60))" "Bucket 1 message 1")"
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$((now - 60))" "Bucket 1 message 2")"

  # Send some messages now
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$now" "Bucket 2 message 1")"
  redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$(make_message "$now" "Bucket 2 message 2")"

  # Now, we expect to only find a total of 4 messages, in 2 buckets (because we only retain 2).
  bucket_count="$(dump_buffers)"

  [[ "$bucket_count" -eq 2 ]]
  [[ "$(count_unique_messages "$STREAM_FILE")" -eq "6" ]]
  [[ "$(count_unique_messages "$BUFFER_FILE")" -eq "4" ]]

  # Finally, we expect the order to be from oldest to newest.
  run cat "$BUFFER_FILE"
  [[ ${lines[0]} =~ "Bucket 1 message 1" ]]
  [[ ${lines[1]} =~ "Bucket 1 message 2" ]]
  [[ ${lines[2]} =~ "Bucket 2 message 1" ]]
  [[ ${lines[3]} =~ "Bucket 2 message 2" ]]
}

@test "It does not run out of memory" {
  # We'll send messages that are about 40kB. We should not be able to store
  # more than 50 of those, so we'll send 100.
  n_messages=100

  ts="$(date +%s)"
  payload="$(head -c "$((3072 * 10))" "/dev/urandom" | base64 | tr --delete '\n')"

  msg="$(make_message "$ts" "$payload")"
  for i in $(seq 1 "$n_messages"); do
    redis-cli EVALSHA "$LOAD_SCRIPT_SHA" 0 "$msg"
  done
  dump_buffers

  # Check that all messages were received, but that some were discarded.
  [[ "$(count_unique_messages "$STREAM_FILE")" -eq "$n_messages" ]]
  [[ "$(count_unique_messages "$BUFFER_FILE")" -lt "$n_messages" ]]
}
