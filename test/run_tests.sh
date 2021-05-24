#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# Install openssl (needed only for tests)
apk add --no-cache openssl

bats /tmp/test

apk del --purge openssl
