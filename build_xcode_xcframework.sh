#!/bin/bash

set -ex

# check parameters, usage: ./build.sh framework_id framework_name build_config build_dir
if [ $# -lt 5 ]; then
  echo "Usage: $0 framework_id framework_name build_config build_dir sub_dir"
  ehco "sub_dir use 'http2' or 'http3'"
  exit 1
fi

echo "Start building framework with parameters: $@"

FRAMEWORK_ID=$1
FRAMEWORK_NAME=$2
BUILD_CONFIG=$3
BUILD_DIR=$4
SUB_DIR=$5

# if build_config is not specified, use release as default
if [ -z "$BUILD_CONFIG" ]; then
  BUILD_CONFIG="Release"
fi

echo "Building configuration '$BUILD_CONFIG'"

build_framework() {
  sdk="$1"
  archs=("${@:2}") # Pass in remaining arguments as array
  arch_flags="${archs[@]/#/-arch }" # Prefix each arch with "-arch"

  xcodebuild -workspace "${FRAMEWORK_NAME}.xcworkspace" -configuration "$BUILD_CONFIG" -scheme "$FRAMEWORK_NAME" -sdk "$sdk" $arch_flags build

  # Directly use the output of xcodebuild -showBuildSettings to avoid re-execution and errors
  local build_settings
  local built_products_dir

  build_settings="$(xcodebuild -workspace "${FRAMEWORK_NAME}.xcworkspace" -configuration "$BUILD_CONFIG" -scheme "$FRAMEWORK_NAME" -sdk "$sdk" $arch_flags -showBuildSettings)"
  built_products_dir=$(echo "$build_settings" | grep " BUILT_PRODUCTS_DIR =" | sed "s/.*= //")
  echo "built_products_dir: ${built_products_dir}"

  eval "FRAMEWORK_PATH_${sdk}='${built_products_dir}/${FRAMEWORK_NAME}.framework'"
}

build_framework iphoneos arm64
build_framework iphonesimulator x86_64 arm64

DEVICE_FRAMEWORK=$(eval echo \$FRAMEWORK_PATH_iphoneos)
SIMULATOR_FRAMEWORK=$(eval echo \$FRAMEWORK_PATH_iphonesimulator)

# cd "$BUILD_DIR"

# mkdir ${FRAMEWORK_ID}

SUB_PATH="${BUILD_DIR}/${SUB_DIR}"
XCFRAME_PATH="${SUB_PATH}/${FRAMEWORK_ID}"

rm -rf "${SUB_PATH}" && mkdir -p "${XCFRAME_PATH}"

# Create xcframework
xcodebuild -create-xcframework -framework "$DEVICE_FRAMEWORK" -framework "$SIMULATOR_FRAMEWORK" -output "${XCFRAME_PATH}/${FRAMEWORK_NAME}.xcframework"

# Remove _CodeSignature directories
echo "Removing _CodeSignature directories."
find "${XCFRAME_PATH}/${FRAMEWORK_NAME}.xcframework" -name '_CodeSignature' -type d -exec rm -rf {} +

if [ "$SUB_DIR" = "http3" ]; then
  echo "SUB_DIR is http3, copy EMASCAResource.bundle."
  cp "cacert.pem" "${XCFRAME_PATH}/cacert.pem"
  cp "EMASCurlHttp3.podspec" "${SUB_PATH}/EMASCurl.podspec"
else
  echo "SUB_DIR is http2"
  cp "EMASCurlHttp2.podspec" "${SUB_PATH}/EMASCurl.podspec"
fi

PATH_PROJECT="$(pwd)"

cd "${SUB_PATH}"

zip -r ${FRAMEWORK_ID}.zip ${FRAMEWORK_ID}

cd "${PATH_PROJECT}"

echo -e "\nBUILD FINISH."
