#!/bin/bash

set -ex

DIR="out"

if [ -d "$DIR" ]; then
  rm -rf "$DIR"
fi

mkdir "$DIR"

./build_openssl.sh
./build_nghttp2.sh
./build_nghttp3.sh
./build_ngtcp2.sh
./build_libcurl_http2.sh
./build_libcurl_http3.sh
./create_EMASCAResource_bundle.sh