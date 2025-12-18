#!/bin/bash
set -ex

ROOT_DIR="$(cd "$(dirname "$0")"; pwd)"
SRC_DIR="$ROOT_DIR/ngtcp2"
OUT_DIR="$ROOT_DIR/out/ngtcp2"
COMMON_OUT="$ROOT_DIR/out"

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

  BUILD_DIR="$OUT_DIR/build-$SDK-$ARCH"
  PREFIX="${OUT_DIR}/artifacts-$SDK-$ARCH"

  rm -rf "$BUILD_DIR" "$PREFIX"
  mkdir -p "$BUILD_DIR" "$PREFIX"

  SDK_PATH="$(xcrun -sdk "$SDK" --show-sdk-path)"

  # 依赖库路径
  SSL_PREFIX="${COMMON_OUT}/openssl/artifacts-$SDK-$ARCH"
  NGHTTP3_PREFIX="${COMMON_OUT}/nghttp3/artifacts-$SDK-$ARCH"

  cd "$BUILD_DIR"

  cmake \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_FLAGS="-I$SSL_PREFIX/include" \
    \
    -DNGTCP2_ENABLE_LIB_ONLY=ON \
    -DNGTCP2_ENABLE_EXAMPLES=OFF \
    -DNGTCP2_ENABLE_APP=OFF \
    -DENABLE_OPENSSL=ON \
    -DENABLE_BORINGSSL=OFF \
    -DHAVE_SSL_SET_QUIC_TLS_CBS=1 \
    \
    -DOPENSSL_ROOT_DIR="$SSL_PREFIX" \
    -DOPENSSL_INCLUDE_DIR="$SSL_PREFIX/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$SSL_PREFIX/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$SSL_PREFIX/lib/libssl.a" \
    \
    -DNGHTTP3_INCLUDE_DIR="$NGHTTP3_PREFIX/include" \
    -DNGHTTP3_LIBRARY="$NGHTTP3_PREFIX/lib/libnghttp3.a" \
    \
    "$SRC_DIR"

  cmake --build . --config Release -- -j8
  cmake --install . --config Release

  mkdir -p "$PREFIX/lib"

  # 打包 libngtcp2.a：主库对象
  NGTCP2_OBJS=$(find . -name '*.o' | grep '/libngtcp2' | grep -v 'crypto_' || true)
  if [ -z "$NGTCP2_OBJS" ]; then
    # 兜底：打包 lib 目录里所有不带 crypto 的 .o
    NGTCP2_OBJS=$(find lib -name '*.o' | grep -v 'crypto_' || true)
  fi
  libtool -static -o "$PREFIX/lib/libngtcp2.a" $NGTCP2_OBJS

  # OpenSSL 3.5.0 使用 crypto_ossl
  # 库已经由 CMake 生成，无需手动打包
done

echo "ngtcp2 built. Per-arch outputs are in: $OUT_DIR/artifacts-<SDK>-<ARCH>/lib"
