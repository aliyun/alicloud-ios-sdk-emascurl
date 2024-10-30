#!/bin/bash

set -ex

cd nghttp2

installPath="$(pwd)/../out/nghttp2"

if [ -d "$installPath" ]; then
  rm -rf "$installPath"
fi

mkdir "$installPath"

autoreconf -fi

DEPLOYMENT_TARGET=12.0

combinations=(
    "ARCH=arm64 SDK=iphoneos"
    "ARCH=arm64 SDK=iphonesimulator"
    "ARCH=x86_64 SDK=iphonesimulator"
)

for combination in "${combinations[@]}"; do
    eval $combination

    CFLAGS="-arch $ARCH -isysroot $(xcrun -sdk $SDK --show-sdk-path) -m$SDK-version-min=$DEPLOYMENT_TARGET"
    ./configure --host=$ARCH-apple-darwin \
                --prefix "${installPath}/artifacts-$SDK-$ARCH" \
                --enable-static \
                --disable-shared \
                --enable-lib-only \
                CFLAGS="$CFLAGS"
    make -j8
    make install

    make clean
done

cd ..
