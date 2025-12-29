#!/bin/bash

set -ex

cd openssl

installPath="$(pwd)/../out/openssl"

if [ -d "$installPath" ]; then
  rm -rf "$installPath"
fi

mkdir "$installPath"

DEPLOYMENT_TARGET=10.0

combinations=(
    "ARCH=arm64 SDK=iphoneos TARGET=ios64-xcrun"
    "ARCH=arm64 SDK=iphonesimulator TARGET=iossimulator-xcrun"
    "ARCH=x86_64 SDK=iphonesimulator TARGET=iossimulator-xcrun"
)

for combination in "${combinations[@]}"; do
    eval $combination

    PREFIX="${installPath}/artifacts-$SDK-$ARCH"
    SDK_PATH="$(xcrun -sdk "$SDK" --show-sdk-path)"
    
    # 清理之前的构建
    make distclean || true

    # 配置 OpenSSL
    if [ "$SDK" = "iphonesimulator" ]; then
        # 模拟器需要明确指定 -target
        export CFLAGS="-arch $ARCH -isysroot $SDK_PATH -mios-simulator-version-min=$DEPLOYMENT_TARGET"
    else
        export CFLAGS="-arch $ARCH -isysroot $SDK_PATH -mios-version-min=$DEPLOYMENT_TARGET"
    fi
    
    ./Configure $TARGET \
        no-shared \
        no-async \
        --prefix="$PREFIX" \
        --openssldir="$PREFIX"

    # 编译和安装
    make -j8
    make install_sw
    
    unset CFLAGS

done

cd ..
