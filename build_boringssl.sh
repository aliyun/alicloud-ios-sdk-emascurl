#!/bin/bash

set -ex

cd boringssl

installPath="$(pwd)/../out/boringssl"

if [ -d "$installPath" ]; then
  rm -rf "$installPath"
fi

mkdir "$installPath"

DEPLOYMENT_TARGET=10.0

combinations=(
    "ARCH=arm64 SDK=iphoneos"
    "ARCH=arm64 SDK=iphonesimulator"
    "ARCH=x86_64 SDK=iphonesimulator"
)

for combination in "${combinations[@]}"; do
    eval $combination

    CFLAGS="-arch $ARCH -isysroot $(xcrun -sdk $SDK --show-sdk-path) -m$SDK-version-min=$DEPLOYMENT_TARGET"

    cmake -DCMAKE_INSTALL_PREFIX="${installPath}/artifacts-$SDK-$ARCH" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=$SDK \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -B build

    make -C build
    make -C build install

    rm -rf build/
done

cd ..
