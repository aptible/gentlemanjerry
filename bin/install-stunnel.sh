#!/bin/bash
set -o errexit
set -o nounset

STUNNEL_VERSION="5.37"
STUNNEL_SHA1SUM="9ec0c64838b3013b38e2cac8e4500219a027831c"

STUNNEL_NAME="stunnel-${STUNNEL_VERSION}"
STUNNEL_ARCHIVE="${STUNNEL_NAME}.tar.gz"
STUNNEL_URL="https://s3.amazonaws.com/aptible-source-archives/${STUNNEL_ARCHIVE}"

STUNNEL_BUILD_DEPS=(build-base linux-headers wget openssl-dev)

apk-install libssl1.0 libcrypto1.0 "${STUNNEL_BUILD_DEPS[@]}"

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
