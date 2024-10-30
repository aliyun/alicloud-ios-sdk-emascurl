#!/bin/bash

set -ex

cd ngtcp2

commonPath="$(pwd)/../out"
installPath="${commonPath}/ngtcp2"

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

    sslPath="${commonPath}/boringssl/artifacts-$SDK-$ARCH"
    nghttp3Path="${commonPath}/nghttp3/artifacts-$SDK-$ARCH"   

    export CFLAGS="-arch $ARCH -isysroot $(xcrun -sdk $SDK --show-sdk-path) -m$SDK-version-min=$DEPLOYMENT_TARGET"
    export CXXFLAGS="${CFLAGS}"
    export LDFLAGS="-L${sslPath}/lib -L${nghttp3Path}/lib -lc++"
    export BORINGSSL_CFLAGS="-I${sslPath}/include"
    export BORINGSSL_LIBS="-lssl -lcrypto"
    export NGHTTP3_CFLAGS="-I${nghttp3Path}/include"
    export NGHTTP3_LIBS="-lnghttp3"
    export PKG_CONFIG_PATH="${nghttp3Path}/lib/pkgconfig"

    ./configure --prefix="${installPath}/artifacts-$SDK-$ARCH" \
                --host=$ARCH-apple-darwin \
                --enable-lib-only \
                --enable-static \
                --disable-shared \
                --with-boringssl \
                --with-libnghttp3 \
                CXX=$(xcrun -find clang++)

    make -j8
    make install

    make clean
done

cd ..
