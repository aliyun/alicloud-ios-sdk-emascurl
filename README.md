# EMASCurl Project
This repository aims to build xcframework for EMASCurl.

## Clone from Git

1. Clone the repository:
    ```bash
    git clone http://gitlab.alibaba-inc.com/alicloud-ams/alicloud-ios-sdk-emascurl.git
    ```
   
2. Change to the project directory:
    ```bash
    cd alicloud-ios-sdk-emascurl
    ```

3. Install dependencies:
    ```bash
    pod install
    ```

## Build libcurl xcframework
Make sure you have installed `automake, autoconf, libtool, pkg-config` before.

1. get submodule reposity
    ```bash
    git submodule update --init --recursive --progress
    ```
   | dependency reposity     | version     |
   |:---------|:---------|
   | curl  | curl-8_10_1  |
   | nghttp2  | v1.64.0  |
   | nghttp3  | v1.1.0  |
   | ngtcp2  | v1.2.0  |
   | boringssl  |  58f3bc83230d2958bb9710bc910972c4f5d382dc  |

2. Run build script
    ```bash
    ./build_libcurl_xcframework.sh
    ```

3. Results will be in the `out` folder
- **libcurl-HTTP2.xcframework**: Supports HTTP1/HTTP2. Build with Secure Transport and nghttp2.
- **libcurl-HTTP3.xcframework**: Supports HTTP1/HTTP2/HTTP3. Build with BoringSSL, nghttp2, nghttp3, and ngtcp2.

## Build EMASCurl xcframework

Make sure you have installed `gem, ruby, xcodeproj` before.

1. Run build script
    ```bash
    ./build_emascurl_xcframework.sh
    ```

2. Results will be in the `Build` folder
- **Build/http2**: the folder contains http2 version EMASCurl xcframework, zip file and podspec
- **Build/http3**: the folder contains http3 version EMASCurl xcframework, zip file and podspec