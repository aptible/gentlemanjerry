#!/bin/bash
set -o errexit
set -o nounset

STUNNEL_VERSION="5.46"
STUNNEL_SHA1SUM="5b6f337e5025c7004cf34f038f579f09fd36c6b0"

STUNNEL_NAME="stunnel-${STUNNEL_VERSION}"
STUNNEL_ARCHIVE="${STUNNEL_NAME}.tar.gz"
STUNNEL_URL="https://s3.amazonaws.com/aptible-source-archives/${STUNNEL_ARCHIVE}"

STUNNEL_BUILD_DEPS=(build-base linux-headers wget openssl-dev)

apk add --no-cache libssl1.0 libcrypto1.0 "${STUNNEL_BUILD_DEPS[@]}"

BUILD_DIR="$(mktemp -d)"
pushd "$BUILD_DIR"

wget "$STUNNEL_URL"
echo "${STUNNEL_SHA1SUM}  ${STUNNEL_ARCHIVE}" | sha1sum -c -
tar -xzf "$STUNNEL_ARCHIVE"

pushd "$STUNNEL_NAME"
./configure --disable-fips
make install
popd

popd
rm -rf "$BUILD_DIR"
apk del "${STUNNEL_BUILD_DEPS[@]}"
