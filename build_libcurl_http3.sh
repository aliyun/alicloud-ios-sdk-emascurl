#!/bin/bash
set -ex

ROOT_DIR="$(cd "$(dirname "$0")"; pwd)"
SRC_DIR="$ROOT_DIR/curl"
OUT_BASE="$ROOT_DIR/out"
OUT_DIR="$OUT_BASE/curl3"

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

  BUILD_DIR="$OUT_DIR/build-$SDK-$ARCH-HTTP3"
  PREFIX="${OUT_DIR}/artifacts-$SDK-$ARCH-HTTP3"

  rm -rf "$BUILD_DIR" "$PREFIX"
  mkdir -p "$BUILD_DIR" "$PREFIX"

  SDK_PATH="$(xcrun -sdk "$SDK" --show-sdk-path)"

  # 依赖路径（用于最后 libtool 拼库）
  SSL_PREFIX="${OUT_BASE}/openssl/artifacts-$SDK-$ARCH"
  NGHTTP2_PREFIX="${OUT_BASE}/nghttp2/artifacts-$SDK-$ARCH"
  NGHTTP3_PREFIX="${OUT_BASE}/nghttp3/artifacts-$SDK-$ARCH"
  NGTCP2_PREFIX="${OUT_BASE}/ngtcp2/artifacts-$SDK-$ARCH"

  cd "$BUILD_DIR"

  # 设置 PKG_CONFIG_PATH
  export PKG_CONFIG_PATH="$SSL_PREFIX/lib/pkgconfig:$NGHTTP3_PREFIX/lib/pkgconfig:$NGTCP2_PREFIX/lib/pkgconfig"

  # 这里只启用 OpenSSL，其它 HTTP/3 相关不用 CMake 管
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
    -DBUILD_CURL_EXE=OFF \
    -DBUILD_LIBCURL=ON \
    -DCURL_DISABLE_LDAP=ON \
    -DCURL_ZLIB=OFF \
    -DCURL_USE_LIBPSL=OFF \
    -DUSE_LIBIDN2=OFF \
    -DCURL_USE_SECTRANSP=OFF \
    -DCURL_USE_OPENSSL=ON \
    -DCURL_USE_SCHANNEL=OFF \
    -DCURL_USE_GSSAPI=OFF \
    \
    -DHTTP_ONLY=OFF \
    \
    -DUSE_NGHTTP2=ON \
    -DNGHTTP2_INCLUDE_DIR="$NGHTTP2_PREFIX/include" \
    -DNGHTTP2_LIBRARY="$NGHTTP2_PREFIX/lib/libnghttp2.a" \
    \
    -DOPENSSL_ROOT_DIR="$SSL_PREFIX" \
    -DOPENSSL_INCLUDE_DIR="$SSL_PREFIX/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$SSL_PREFIX/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$SSL_PREFIX/lib/libssl.a" \
    \
    -DUSE_NGHTTP3=ON \
    -DNGHTTP3_INCLUDE_DIR="$NGHTTP3_PREFIX/include" \
    -DNGHTTP3_LIBRARY="$NGHTTP3_PREFIX/lib/libnghttp3.a" \
    \
    -DUSE_NGTCP2=ON \
    -DNGTCP2_INCLUDE_DIR="$NGTCP2_PREFIX/include" \
    -DNGTCP2_LIBRARY="$NGTCP2_PREFIX/lib/libngtcp2.a" \
    -DNGTCP2_CRYPTO_OSSL_LIBRARY="$NGTCP2_PREFIX/lib/libngtcp2_crypto_ossl.a" \
    -DCMAKE_C_FLAGS="-DUSE_HTTP3=1" \
    \
    "$SRC_DIR"

  cmake --build . --config Release -- -j8
  cmake --install . --config Release

  # 方案1：ngtcp2 + OpenSSL 3.5.0
  libtool -static -o "${PREFIX}/libcurl.a" \
    "${PREFIX}/lib/libcurl.a" \
    "${NGHTTP2_PREFIX}/lib/libnghttp2.a" \
    "${SSL_PREFIX}/lib/libssl.a" \
    "${SSL_PREFIX}/lib/libcrypto.a" \
    "${NGHTTP3_PREFIX}/lib/libnghttp3.a" \
    "${NGTCP2_PREFIX}/lib/libngtcp2.a" \
    "${NGTCP2_PREFIX}/lib/libngtcp2_crypto_ossl.a"
done

# 合并两个模拟器架构成一个 fat lib
lipo \
  "${OUT_DIR}/artifacts-iphonesimulator-arm64-HTTP3/libcurl.a" \
  "${OUT_DIR}/artifacts-iphonesimulator-x86_64-HTTP3/libcurl.a" \
  -create -output "${OUT_DIR}/libcurl.a"

# 生成 xcframework
FRAMEWORK_PATH="${OUT_BASE}/libcurl-HTTP3.xcframework"
rm -rf "$FRAMEWORK_PATH"

xcodebuild -create-xcframework \
  -library "${OUT_DIR}/artifacts-iphoneos-arm64-HTTP3/libcurl.a" \
  -headers "${OUT_DIR}/artifacts-iphoneos-arm64-HTTP3/include" \
  -library "${OUT_DIR}/libcurl.a" \
  -headers "${OUT_DIR}/artifacts-iphonesimulator-arm64-HTTP3/include" \
  -output "$FRAMEWORK_PATH"
