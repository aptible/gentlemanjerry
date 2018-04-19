#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

SSL_TEST_CLASS="SslTest"

# Install full JDK to compile SSL test. Purge it before we run the tests,
# to ensure Gentleman Jerry can still boot (!).
apk add --no-cache "${JDK_VERSION}"
/usr/lib/jvm/default-jvm/bin/javac "/tmp/test/${SSL_TEST_CLASS}.java"
apk del --purge "${JDK_VERSION}"

# Install openssl (needed only for tests)
apk add --no-cache openssl

bats /tmp/test

rm "/tmp/test/${SSL_TEST_CLASS}.class"
apk del --purge openssl
