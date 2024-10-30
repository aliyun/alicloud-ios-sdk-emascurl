#!/bin/bash

set -ex

FRAMEWORK_ID="emascurl"
FRAMEWORK_NAME="EMASCurl"
BUILD_CONFIG="release"
BUILD_DIR="`pwd`/Build"

# remove and make Build directory
rm -rf Build && mkdir Build

sh Build/ios-xcframework-build-script/build.sh $FRAMEWORK_ID $FRAMEWORK_NAME $BUILD_CONFIG $BUILD_DIR "http2"
