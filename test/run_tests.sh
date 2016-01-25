#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


SSL_TEST_CLASS="SslTest"

# Install full JDK to compile SSL test. Purge it before we run the tests,
# to ensure Gentleman Jerry can still boot (!).
apk-install "${JDK_VERSION}"
/usr/lib/jvm/default-jvm/bin/javac "/tmp/test/${SSL_TEST_CLASS}.java"
apk del --purge "${JDK_VERSION}"

bats /tmp/test

rm "/tmp/test/${SSL_TEST_CLASS}.class"
