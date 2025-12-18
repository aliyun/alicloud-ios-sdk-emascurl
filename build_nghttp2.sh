#!/bin/bash
set -ex

ROOT_DIR="$(cd "$(dirname "$0")"; pwd)"
SRC_DIR="$ROOT_DIR/nghttp2"
OUT_DIR="$ROOT_DIR/out/nghttp2"

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

  # 先用 CMake 生成构建系统
  cmake \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    \
    -DENABLE_APP=OFF \
    -DENABLE_HPACK_TOOLS=OFF \
    -DENABLE_EXAMPLES=OFF \
    -DENABLE_LIB_ONLY=ON \
    "$SRC_DIR"

  # 正常编译（CMake 会生成对象文件）
  cmake --build . --config Release -- -j8
  cmake --install . --config Release

  # 手动收集所有 nghttp2 的对象文件，打包成静态库
  # nghttp2 的 lib 通常在 lib/ 目录下
  # 找出所有与 nghttp2 库相关的 .o 文件
  OBJ_LIST=$(find . -name '*.o' | grep '/libnghttp2' || true)
  if [ -z "$OBJ_LIST" ]; then
    # 如果上面的 grep 没找到，就退而求其次：打包 lib 目录下所有 .o
    OBJ_LIST=$(find lib -name '*.o')
  fi

  mkdir -p "$PREFIX/lib"
  # 用 libtool 或 ar 打包
  # macOS 下推荐用 libtool -static
  libtool -static -o "$PREFIX/lib/libnghttp2.a" $OBJ_LIST
done

echo "nghttp2 built. Per-arch outputs are in: $OUT_DIR/artifacts-<SDK>-<ARCH>/lib/libnghttp2.a"
