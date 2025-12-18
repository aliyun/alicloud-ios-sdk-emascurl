#!/bin/bash
set -ex

ROOT_DIR="$(cd "$(dirname "$0")"; pwd)"
SRC_DIR="$ROOT_DIR/curl"
OUT_BASE="$ROOT_DIR/out"
OUT_DIR="$OUT_BASE/curl2"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

DEPLOYMENT_TARGET=12.0

combinations=(
  "ARCH=arm64   SDK=iphoneos"
  "ARCH=arm64   SDK=iphonesimulator"
  "ARCH=x86_64  SDK=iphonesimulator"
)

for combination in "${combinations[@]}"; do
  eval "$combination"

  BUILD_DIR="$OUT_DIR/build-$SDK-$ARCH-HTTP2"
  PREFIX="${OUT_DIR}/artifacts-$SDK-$ARCH-HTTP2"

  rm -rf "$BUILD_DIR" "$PREFIX"
  mkdir -p "$BUILD_DIR" "$PREFIX"

  SDK_PATH="$(xcrun -sdk "$SDK" --show-sdk-path)"

  # nghttp2 路径
  NGHTTP2_PREFIX="${OUT_BASE}/nghttp2/artifacts-$SDK-$ARCH"

  cd "$BUILD_DIR"

  cmake \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_CURL_EXE=OFF \        # 新增：不构建 curl 命令行工具
    -DBUILD_LIBCURL=ON \          # 新增：只构建 libcurl
    -DCURL_DISABLE_LDAP=ON \
    -DCURL_ZLIB=OFF \
    -DCURL_USE_LIBPSL=OFF \
    -DCURL_USE_LIBIDN2=OFF \
    -DCURL_USE_SECTRANSP=ON \
    -DCURL_USE_OPENSSL=OFF \
    -DCURL_USE_SCHANNEL=OFF \
    -DCURL_USE_GSSAPI=OFF \
    \
    -DHTTP_ONLY=OFF \
    -DUSE_NGHTTP2=ON \
    -DNGHTTP2_INCLUDE_DIR="$NGHTTP2_PREFIX/include" \
    -DNGHTTP2_LIBRARY="$NGHTTP2_PREFIX/lib/libnghttp2.a" \
    \
    "$SRC_DIR"

  cmake --build . --config Release -- -j8
  cmake --install . --config Release

  # 对齐你原脚本：curl + nghttp2 打成一个 libcurl.a
  libtool -static -o "${PREFIX}/libcurl.a" \
    "${PREFIX}/lib/libcurl.a" \
    "${NGHTTP2_PREFIX}/lib/libnghttp2.a"
done

# 合并两个模拟器架构成一个 fat lib
lipo \
  "${OUT_DIR}/artifacts-iphonesimulator-arm64-HTTP2/libcurl.a" \
  "${OUT_DIR}/artifacts-iphonesimulator-x86_64-HTTP2/libcurl.a" \
  -create -output "${OUT_DIR}/libcurl.a"

# 生成 xcframework
FRAMEWORK_PATH="${OUT_BASE}/libcurl-HTTP2.xcframework"
rm -rf "$FRAMEWORK_PATH"

xcodebuild -create-xcframework \
  -library "${OUT_DIR}/artifacts-iphoneos-arm64-HTTP2/libcurl.a" \
  -headers "${OUT_DIR}/artifacts-iphoneos-arm64-HTTP2/include" \
  -library "${OUT_DIR}/libcurl.a" \
  -headers "${OUT_DIR}/artifacts-iphonesimulator-arm64-HTTP2/include" \
  -output "$FRAMEWORK_PATH"
