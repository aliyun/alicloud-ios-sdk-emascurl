#!/bin/bash

set -ex

cd curl

commonPath="$(pwd)/../out"
installPath="${commonPath}/curl2"

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
                --prefix="${installPath}/artifacts-$SDK-$ARCH-HTTP2" \
                --enable-static \
                --disable-shared \
                --without-libpsl \
                --without-libidn2 \
                --without-apple-idn \
                --with-secure-transport \
                --with-nghttp2="${commonPath}/nghttp2/artifacts-$SDK-$ARCH" \
                CFLAGS="$CFLAGS"

    make -j8
    make install

    libtool -static -o "${installPath}/artifacts-$SDK-$ARCH-HTTP2/libcurl.a" "${installPath}/artifacts-$SDK-$ARCH-HTTP2/lib/libcurl.a" \
                    "${commonPath}/nghttp2/artifacts-$SDK-$ARCH/lib/libnghttp2.a"

    make clean
done

lipo "${installPath}/artifacts-iphonesimulator-arm64-HTTP2/libcurl.a" \
     "${installPath}/artifacts-iphonesimulator-x86_64-HTTP2/libcurl.a" \
     -create -output "${installPath}/libcurl.a"

frameworkPath="${installPath}/../libcurl-HTTP2.xcframework"

if [ -d "$frameworkPath" ]; then
  rm -rf "$frameworkPath"
fi

xcodebuild -create-xcframework \
-library "${installPath}/artifacts-iphoneos-arm64-HTTP2/libcurl.a" -headers "${installPath}/artifacts-iphoneos-arm64-HTTP2/include" \
-library "${installPath}/libcurl.a" -headers "${installPath}/artifacts-iphonesimulator-arm64-HTTP2/include" \
-output "${frameworkPath}"

cd ..
