#!/bin/bash

set -ex

cd curl

commonPath="$(pwd)/../out"
installPath="${commonPath}/curl3"

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
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-L${commonPath}/boringssl/artifacts-$SDK-$ARCH/lib -lc++"

    export LDFLAGS
    export CFLAGS
    export CXXFLAGS

    ./configure --host=$ARCH-apple-darwin \
                --prefix="${installPath}/artifacts-$SDK-$ARCH-HTTP3" \
                --enable-static \
                --disable-shared \
                --without-libpsl \
                --without-libidn2 \
                --without-apple-idn \
                --with-openssl="${commonPath}/boringssl/artifacts-$SDK-$ARCH" \
                --with-nghttp2="${commonPath}/nghttp2/artifacts-$SDK-$ARCH" \
                --with-nghttp3="${commonPath}/nghttp3/artifacts-$SDK-$ARCH" \
                --with-ngtcp2="${commonPath}/ngtcp2/artifacts-$SDK-$ARCH" \
                CXX=$(xcrun -find clang++) \
                CFLAGS="$CFLAGS" \
                LDFLAGS="$LDFLAGS" \
                CXXFLAGS="$CXXFLAGS"

    make -j8
    make install

    libtool -static -o "${installPath}/artifacts-$SDK-$ARCH-HTTP3/libcurl.a" "${installPath}/artifacts-$SDK-$ARCH-HTTP3/lib/libcurl.a" \
                    "${commonPath}/nghttp2/artifacts-$SDK-$ARCH/lib/libnghttp2.a" \
                    "${commonPath}/boringssl/artifacts-$SDK-$ARCH/lib/libssl.a" \
                    "${commonPath}/boringssl/artifacts-$SDK-$ARCH/lib/libcrypto.a" \
                    "${commonPath}/nghttp3/artifacts-$SDK-$ARCH/lib/libnghttp3.a" \
                    "${commonPath}/ngtcp2/artifacts-$SDK-$ARCH/lib/libngtcp2_crypto_boringssl.a" \
                    "${commonPath}/ngtcp2/artifacts-$SDK-$ARCH/lib/libngtcp2.a"

    make clean
done

lipo "${installPath}/artifacts-iphonesimulator-arm64-HTTP3/libcurl.a" \
     "${installPath}/artifacts-iphonesimulator-x86_64-HTTP3/libcurl.a" \
     -create -output "${installPath}/libcurl.a"

frameworkPath="${installPath}/../libcurl-HTTP3.xcframework"

if [ -d "$frameworkPath" ]; then
  rm -rf "$frameworkPath"
fi

xcodebuild -create-xcframework \
-library "${installPath}/artifacts-iphoneos-arm64-HTTP3/libcurl.a" -headers "${installPath}/artifacts-iphoneos-arm64-HTTP3/include" \
-library "${installPath}/libcurl.a" -headers "${installPath}/artifacts-iphonesimulator-arm64-HTTP3/include" \
-output "${frameworkPath}"

cd ..
