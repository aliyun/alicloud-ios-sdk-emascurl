#!/bin/bash

set -ex

DIR="out"

if [ -d "$DIR" ]; then
  rm -rf "$DIR"
fi

mkdir "$DIR"


./build_nghttp2.sh
./build_libcurl_http2.sh