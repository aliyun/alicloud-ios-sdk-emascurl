<!-- # EMASCurl Project
This repository aims to build xcframework for EMASCurl.

## Clone from Git

1. Clone the repository:
    ```bash
    git clone repo_url
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
- **Build/http2**: the folder contains http2 version EMASCurl xcframework, zip file and podspec file
- **Build/http3**: the folder contains http3 version EMASCurl xcframework, zip file and podspec file -->

# EMASCurl

[![GitHub version](https://badge.fury.io/gh/aliyun%2Falicloud-ios-sdk-emascurl.git.svg)](https://badge.fury.io/gh/aliyun%2Falicloud-ios-sdk-emascurl.git)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)

## 关于

EMASCurl是阿里云EMAS团队提供的基于[libcurl](https://github.com/curl/curl)的iOS平台网络库框架，能够与阿里云[HTTPDNS](https://www.aliyun.com/product/httpdns)配合使用，以降低iOS开发者接入[HTTPDNS](https://www.aliyun.com/product/httpdns)的门槛。

## 版本

- 当前版本：1.0.1-http2-beta

## EMASCurl构建

本章节介绍如何使用本仓库本地构建EMASCurl xcframework。

### 构建工具安装

构建过程中需要使用git克隆代码、使用automake, autoconf, libtool, pkg-config等构建工具、使用gem, ruby, xcodeproj等工具，请您确认这些命令行工具已经安装在本机，如果尚未安装参考以下安装命令：

```shell
brew install automake autoconf libtool pkg-config
brew install ruby
gem install xcodeproj
```

### 拉取子模块

本仓库以submodule的形式管理依赖的仓库，在克隆后需要手动拉取子模块：

```shell
git submodule update --init --recursive --progress
```

所依赖的子模块版本信息如下：
| dependency repository     | version     |
|:---------|:---------|
| curl  | curl-8_10_1  |
| nghttp2  | v1.64.0  |

### 构建libcurl xcframework

```shell
./build_libcurl_xcframework.sh
```

运行完脚本后，在`out`文件夹下会生成**libcurl-HTTP2.xcframework**。

### 构建EMASCurl xcframework

```shell
pod install --repo-update
./build_emascurl_xcframework.sh
```
运行完脚本后，在`Build/http2/emascurl`文件夹下会生成**EMASCurl.xcframework**，本框架目前支持HTTP1、HTTP2。

## EMASCurl集成

本章节介绍如何将EMASCurl添加到您的应用中。

我们提供了cocoapods引入依赖和本地依赖两种集成方式，推荐工程使用cocoapods管理依赖。

### cocoapods引入依赖

#### 1. 指定Master仓库和阿里云仓库

EMASCurl和其他EMAS产品的iOS SDK，都是发布到阿里云EMAS官方维护的github仓库中，因此，您需要在您的Podfile文件中包含该仓库地址。

```shell
source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/aliyun/aliyun-specs.git'
```

#### 2. 添加依赖

为您需要依赖EMASCurl的target添加如下依赖。

```shell
use_framework!

pod 'EMASCurl', '1.0.1-http2-beta'
```

#### 3. 安装依赖

在您的Terminal中进入Podfile所在目录，执行以下命令安装依赖。

```shell
pod install --repo-update
```

### 本地手动集成依赖

#### 1. 将framework文件添加到工程中

您需要首先按照**EMASCurl构建**的步骤在本地构建出**EMASCurl.xcframework**，然后在xcode工程项目中(Build Phases -> Link Binary With Libraries)添加对于**EMASCurl.xcframework**的依赖。

#### 2. 添加Linker Flags

EMASCurl会使用zlib进行HTTP压缩与解压，因此您需要为应用的TARGETS -> Build Settings -> Linking -> Other Linker Flags添加上`-lz`与`-ObjC`。

## EMASCurl使用

完成**EMASCurl集成**后，您可以根据头文件中的API(位于文件MASCurlProtocol.h)使用EMASCurl，具体使用方式可以参考EMASCurlDemo中的示例。

## EMASCurlDemo运行

您需要首先按照**EMASCurl构建**在本地构建出**EMASCurl.xcframework**，构建脚本会自动将构建出的**EMASCurl.xcframework**集成到EMASCurlDemo中。使用xcode打开EMASCurl.xcworkspace工程即可运行。

## License

- Apache 2.0

## 联系我们

- [阿里云HTTPDNS官方文档中心](https://www.aliyun.com/product/httpdns#Docs)
- 阿里云官方技术支持：[提交工单](https://workorder.console.aliyun.com/#/ticket/createIndex)
- 阿里云EMAS开发交流钉钉群：35248489