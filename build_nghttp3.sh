#!/bin/bash
set -ex

ROOT_DIR="$(cd "$(dirname "$0")"; pwd)"
SRC_DIR="$ROOT_DIR/nghttp3"
OUT_DIR="$ROOT_DIR/out/nghttp3"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

DEPLOYMENT_TARGET=10.0

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

  cd "$BUILD_DIR"

  # 先用 CMake 生成构建系统（让它把所有 .o 编出来）
  cmake \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DNGHTTP3_BUILD_LIB_ONLY=ON \
    -DNGHTTP3_BUILD_EXAMPLES=OFF \
    "$SRC_DIR"

  cmake --build . --config Release -- -j8
  cmake --install . --config Release

  # 手动打一个静态库 libnghttp3.a
  # 优先找 lib 目录下的 .o；如果没有，再兜底所有 .o
  OBJ_LIST=$(find . -name '*.o' | grep '/libnghttp3' || true)
  if [ -z "$OBJ_LIST" ]; then
    OBJ_LIST=$(find lib -name '*.o')
  fi

  mkdir -p "$PREFIX/lib"
  libtool -static -o "$PREFIX/lib/libnghttp3.a" $OBJ_LIST
done

echo "nghttp3 built. Per-arch outputs are in: $OUT_DIR/artifacts-<SDK>-<ARCH>/lib/libnghttp3.a"
