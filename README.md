# EMAS iOS网络解决方案

[![GitHub version](https://badge.fury.io/gh/aliyun%2Falicloud-ios-sdk-emascurl.git.svg)](https://badge.fury.io/gh/aliyun%2Falicloud-ios-sdk-emascurl.git)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)

EMAS iOS网络解决方案是阿里云EMAS团队为iOS开发者提供的完整网络库适配方案，能够与阿里云[HTTPDNS](https://www.aliyun.com/product/httpdns)配合使用，为iOS应用提供高性能、稳定可靠的网络服务。

## 方案选择指南

目前EMAS提供两种网络架构方案，您可以根据应用需求选择合适的方案：

### EMASCurl - 协议拦截方案（推荐）

**适用场景**：在 NSURLSession 接入 HTTPDNS，且需要兼容 iOS 10.0+ 全量系统版本、获得更精细的请求控制与统一的性能指标采集时，优先使用 EMASCurl。

### EMASLocalProxy - 统一代理方案（WKWebView）

**适用场景**：在 iOS 17.0+ 系统为 WKWebView 配置代理与 HTTPDNS 能力。低于 iOS 17 的系统不支持 WKWebView 代理。

根据 Apple 官方统计（截至 2025 年 6 月 4 日），iOS 17+ 已占较高比例。考虑到 HTTPDNS 为 WKWebView 场景带来防劫持、调度精准、解析及时生效等非功能性提升，建议在使用本方案，在 iOS 17+ 的系统上支持HTTPDNS，iOS 16 及以下的版本也不会带来副作用。随着长尾用户逐渐升级到更新的系统，最终所有用户都可以享受到 HTTPDNS 带来的收益。

### 方案对比

| 特性 | EMASCurl | EMASLocalProxy |
|:---|:---:|:---:|
| **iOS版本要求** | iOS 10.0+ | iOS 17.0+（<17 有兼容差异） |
| **NSURLSession支持** | ✅ 协议拦截 | ✅ iOS17+ 原生代理；<17 仅HTTPS |
| **WKWebView支持** | ❌ | ✅ iOS17+ 原生代理；<17 ❌ |
| **配置复杂度** | 中等 | 简单 |
| **HTTPDNS集成** | ✅ | ✅ |
| **维护成本** | 中等 | 低 |

## 目录
- [EMAS iOS网络解决方案](#emas-ios网络解决方案)
  - [方案选择指南](#方案选择指南)
    - [EMASCurl - 协议拦截方案（推荐）](#emascurl---协议拦截方案推荐)
    - [EMASLocalProxy - 统一代理方案（WKWebView）](#emaslocalproxy---统一代理方案wkwebview)
    - [方案对比](#方案对比)
  - [目录](#目录)
  - [EMASCurl - 协议拦截方案](#emascurl---协议拦截方案)
    - [简介](#简介)
    - [快速入门](#快速入门)
      - [从CocoaPods引入依赖](#从cocoapods引入依赖)
      - [使用EMASCurl发送网络请求](#使用emascurl发送网络请求)
    - [构建EMASCurl](#构建emascurl)
      - [构建工具安装](#构建工具安装)
      - [拉取子模块](#拉取子模块)
      - [构建libcurl.xcframework](#构建libcurlxcframework)
      - [构建EMASCurl xcframework](#构建emascurl-xcframework)
    - [集成EMASCurl](#集成emascurl)
      - [CocoaPods引入依赖](#cocoapods引入依赖)
        - [指定Master仓库和阿里云仓库](#指定master仓库和阿里云仓库)
        - [添加依赖](#添加依赖)
        - [安装依赖](#安装依赖)
      - [本地手动集成依赖](#本地手动集成依赖)
        - [将framework文件添加到工程中](#将framework文件添加到工程中)
        - [添加Linker Flags](#添加linker-flags)
        - [添加CA证书文件路径（如果使用自签名证书）](#添加ca证书文件路径如果使用自签名证书)
    - [使用EMASCurl](#使用emascurl)
      - [开启EMASCurl拦截](#开启emascurl拦截)
        - [拦截`NSURLSessionConfiguration`](#拦截nsurlsessionconfiguration)
        - [拦截`sharedSession`](#拦截sharedsession)
      - [与HTTPDNS配合使用](#与httpdns配合使用)
      - [选择HTTP版本](#选择http版本)
      - [设置CA证书文件路径](#设置ca证书文件路径)
      - [设置Cookie存储](#设置cookie存储)
      - [设置连接超时](#设置连接超时)
      - [设置上传进度回调](#设置上传进度回调)
      - [设置性能指标回调](#设置性能指标回调)
        - [全局综合性能指标回调（强烈推荐）](#全局综合性能指标回调强烈推荐)
        - [单个请求性能指标回调（已废弃）](#单个请求性能指标回调已废弃)
      - [开启调试日志](#开启调试日志)
        - [设置日志级别](#设置日志级别)
        - [组件化日志](#组件化日志)
        - [设置自定义日志处理器](#设置自定义日志处理器)
      - [设置请求拦截域名白名单和黑名单](#设置请求拦截域名白名单和黑名单)
      - [设置Gzip压缩](#设置gzip压缩)
      - [设置内部重定向支持](#设置内部重定向支持)
      - [设置公钥固定 (Public Key Pinning)](#设置公钥固定-public-key-pinning)
      - [设置证书校验](#设置证书校验)
      - [设置域名校验](#设置域名校验)
      - [设置手动代理服务器](#设置手动代理服务器)
      - [设置HTTP缓存](#设置http缓存)
  - [EMASLocalProxy - 统一代理方案](#emaslocalproxy---统一代理方案)
    - [已知限制](#已知限制)
    - [简介](#简介-1)
    - [从CocoaPods引入依赖](#从cocoapods引入依赖-1)
    - [WKWebView集成](#wkwebview集成)
    - [与HTTPDNS配合使用](#与httpdns配合使用-1)
    - [调试和日志](#调试和日志)
  - [License](#license)
  - [联系我们](#联系我们)


## EMASCurl - 协议拦截方案

### 简介

EMASCurl是阿里云EMAS团队提供的基于[libcurl](https://github.com/curl/curl)的iOS平台网络库框架，通过NSURLProtocol拦截机制为iOS应用提供高性能的网络服务。EMASCurl具有以下特性：

- **广泛兼容**：支持iOS 10.0+系统版本
- **协议拦截**：通过NSURLProtocol拦截网络请求
- **HTTP/2支持**：基于libcurl的HTTP/2实现
- **丰富功能**：提供缓存、性能监控、SSL配置等功能
- **HTTPDNS集成**：与阿里云HTTPDNS服务深度集成
- **精细控制**：提供详细的网络请求控制选项

### 快速入门

#### 从CocoaPods引入依赖

在您的`Podfile`文件中添加如下依赖：

```ruby
source 'https://github.com/aliyun/aliyun-specs.git'

target 'yourAppTarget' do
    use_framework!

    pod 'EMASCurl', 'x.x.x'
end
```

当前最新版本：1.4.2

在您的Terminal中进入`Podfile`所在目录，执行以下命令安装依赖：


```shell
pod install --repo-update
```

#### 使用EMASCurl发送网络请求


首先，创建EMASCurl配置并安装到您的`NSURLSessionConfiguration`。


```objc
// 实现自定义DNS解析器（例如使用HTTPDNS）
@interface MyDNSResolver : NSObject <EMASCurlProtocolDNSResolver>
@end

@implementation MyDNSResolver
+ (NSString *)resolveDomain:(NSString *)domain {
    // 这里可以接入HTTPDNS或其他DNS服务
    // 返回解析后的IP地址，多个IP用逗号分隔
    return @"192.168.1.100,192.168.1.101";
}
@end

// 创建EMASCurl配置
EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
curlConfig.dnsResolver = [MyDNSResolver class];  // 设置DNS解析器
curlConfig.connectTimeoutInterval = 3.0;  // 3秒连接超时

// 创建并配置NSURLSession
NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:curlConfig];
```

之后，EMASCurl可以拦截此`NSURLSessionConfiguration`创建的`NSURLSession`发起的请求，并使用自定义的DNS解析器。


```objc
NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                     delegate:nil
                                                delegateQueue:[NSOperationQueue mainQueue]];

NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (error) {
        NSLog(@"请求失败，错误信息: %@", error.localizedDescription);
        return;
    }
    NSLog(@"响应: %@", response);
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"响应体: %@", body);
}];

[dataTask resume];
```

### 构建EMASCurl

本章节介绍如何使用本仓库本地构建EMASCurl `xcframework`。

#### 构建工具安装

构建过程中需要使用`git`克隆代码、使用`automake`、`autoconf`、`libtool`、`pkg-config`等构建工具、使用`gem`、`ruby`、`xcodeproj`等工具，请您确认这些命令行工具已经安装在本机。如果尚未安装，请参考以下安装命令：

```shell
brew install automake autoconf libtool pkg-config
brew install ruby
gem install xcodeproj
```

#### 拉取子模块

本仓库以`submodule`的形式管理依赖的仓库，在克隆后需要手动拉取子模块。

```shell
git submodule update --init --recursive --progress
```

所依赖的子模块版本信息如下：

| 依赖仓库         | 版本        |
|:-----------------|:------------|
| curl             | curl-8_10_1 |
| nghttp2         | v1.64.0     |

#### 构建libcurl.xcframework

```shell
./build_libcurl_xcframework.sh
```

运行完脚本后，在`out`文件夹下会生成**libcurl-HTTP2.xcframework**。

#### 构建EMASCurl xcframework

```shell
pod install --repo-update
./build_emascurl_xcframework.sh
```
运行完脚本后，在`Build/http2/emascurl`文件夹下会生成**EMASCurl.xcframework**，本框架目前支持HTTP1、HTTP2。

### 集成EMASCurl

本章节介绍如何将EMASCurl添加到您的应用中。

我们提供了CocoaPods引入依赖和本地手动集成两种方式，推荐工程使用CocoaPods管理依赖。

#### CocoaPods引入依赖

##### 指定Master仓库和阿里云仓库

EMASCurl和其他EMAS产品的iOS SDK，都是发布到阿里云EMAS官方维护的GitHub仓库中，因此，您需要在您的`Podfile`文件中包含该仓库地址。

```ruby
source 'https://github.com/aliyun/aliyun-specs.git'
```

##### 添加依赖

为您需要依赖EMASCurl的target添加如下依赖。

```ruby
use_framework!

pod 'EMASCurl', 'x.x.x'
```

##### 安装依赖

在您的Terminal中进入`Podfile`所在目录，执行以下命令安装依赖。

```shell
pod install --repo-update
```

#### 本地手动集成依赖

##### 将framework文件添加到工程中

您需要首先按照**EMASCurl构建**的步骤在本地构建出**EMASCurl.xcframework**，然后在Xcode工程项目中（`Build Phases` -> `Link Binary With Libraries`）添加对于**EMASCurl.xcframework**的依赖。

##### 添加Linker Flags

EMASCurl会使用`zlib`进行HTTP压缩与解压，因此您需要为应用的TARGETS -> Build Settings -> Linking -> Other Linker Flags添加上`-lz`与`-ObjC`。

##### 添加CA证书文件路径（如果使用自签名证书）

如果您使用自签名证书，还需将CA证书文件路径设置到EMASCurl中，具体请参考[使用EMASCurl](#使用emascurl)章节中的相关内容。

### 使用EMASCurl

#### 开启EMASCurl拦截

目前EMASCurl有两种开启方式，第一种方式是拦截指定`NSURLSessionConfiguration`创建的`NSURLSession`发起的请求，第二种方式是拦截全局的`sharedSession`发起的请求。

##### 拦截`NSURLSessionConfiguration`

```objc
+ (void)installIntoSessionConfiguration:(nonnull NSURLSessionConfiguration *)sessionConfiguration
                       withConfiguration:(nonnull EMASCurlConfiguration *)configuration;
```

首先，创建EMASCurl配置并安装到您的`NSURLSessionConfiguration`。

```objc
// 创建自定义配置
EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
curlConfig.connectTimeoutInterval = 3.0;
curlConfig.enableBuiltInGzip = YES;
curlConfig.enableBuiltInRedirection = YES;
curlConfig.cacheEnabled = YES;

// 安装到session配置
NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:curlConfig];
```

之后，EMASCurl可以拦截此`NSURLSessionConfiguration`创建的`NSURLSession`发起的请求。

```objc
NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                     delegate:nil
                                                delegateQueue:[NSOperationQueue mainQueue]];

NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (error) {
        NSLog(@"请求失败，错误信息: %@", error.localizedDescription);
        return;
    }
    NSLog(@"响应: %@", response);
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"响应体: %@", body);
}];

[dataTask resume];
```

##### 拦截`sharedSession`

```objc
+ (void)registerCurlProtocol;
```

首先，开启对于`sharedSession`的拦截。

```objc
[EMASCurlProtocol registerCurlProtocol];
```

之后，EMASCurl可以拦截`sharedSession`发起的请求。

```objc
NSURLSession *session = [NSURLSession sharedSession];

NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (error) {
        NSLog(@"请求失败，错误信息: %@", error.localizedDescription);
        return;
    }
    NSLog(@"响应: %@", response);
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"响应体: %@", body);
}];

[dataTask resume];
```

假如您想取消对于`sharedSession`的拦截，可以调用以下API：

```objc
+ (void)unregisterCurlProtocol;
```

#### 与HTTPDNS配合使用

EMASCurl开放了便捷的DNS hook接口，便于与HTTPDNS配合使用。只需要实现以下的DNS接口：

```objc
@protocol EMASCurlProtocolDNSResolver <NSObject>

+ (nullable NSString *)resolveDomain:(nonnull NSString *)domain;

@end
```

例如：

```objc
@interface MyDNSResolver : NSObject <EMASCurlProtocolDNSResolver>

@end

@implementation MyDNSResolver

+ (nullable NSString *)resolveDomain:(nonnull NSString *)domain {
    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
    HttpdnsResult* result = [httpdns resolveHostSyncNonBlocking:domain byIpType:HttpdnsQueryIPTypeBoth];
    NSLog(@"httpdns resolve result: %@", result);
    if (result) {
        if(result.hasIpv4Address || result.hasIpv6Address) {
            NSMutableArray<NSString *> *allIPs = [NSMutableArray array];
            if (result.hasIpv4Address) {
                [allIPs addObjectsFromArray:result.ips];
            }
            if (result.hasIpv6Address) {
                [allIPs addObjectsFromArray:result.ipv6s];
            }
            NSString *combinedIPs = [allIPs componentsJoinedByString:@","];
            return combinedIPs;
        }
    }
    return nil;
}

@end
```

然后在EMASCurl配置中设置DNS解析器：

```objc
// 创建配置并设置DNS解析器
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.dnsResolver = [MyDNSResolver class];

// 应用配置到session
NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:config];
```

#### 选择HTTP版本

EMASCurl默认使用HTTP2版本。您可以在配置中指定HTTP版本：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
// 默认已经是HTTP2，无需设置
// 如需使用HTTP/1.1：
config.httpVersion = HTTP1;  // 使用HTTP/1.1
```

**HTTP1**: 使用HTTP1.1
**HTTP2**: 首先尝试使用HTTP2，如果与服务器的HTTP2协商失败，则会退回到HTTP1.1

#### 设置CA证书文件路径

如果您的服务器使用自签名证书，您需要在配置中设置CA证书文件的路径，以确保EMASCurl能够正确验证SSL/TLS连接。

例如：

```objc
NSString *caFilePath = [[NSBundle mainBundle] pathForResource:@"my_ca" ofType:@"pem"];

EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.caFilePath = caFilePath;
```

#### 设置Cookie存储

EMASCurl默认开启内部Cookie存储功能，但只支持到[RFC 6265]标准。Cookie存储目前仍然是全局设置：

```objc
// 全局启用或禁用Cookie存储
[EMASCurlProtocol setBuiltInCookieStorageEnabled:NO];  // 禁用
[EMASCurlProtocol setBuiltInCookieStorageEnabled:YES]; // 启用（默认）
```

如果您选择关闭内置Cookie存储，在依赖cookie能力时，需要自行处理请求/响应中的cookie字段。

#### 设置连接超时

`NSURLSession`未提供设置连接超时的方式，因此EMASCurl单独提供了此功能。您可以在配置中设置连接超时时间：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.connectTimeoutInterval = 3.0;  // 设置连接超时为3秒（默认为2.5秒）

// 应用配置
NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:config];
```

对于请求的整体超时时间，请直接配置`NSURLRequest`中的`timeoutInterval`进行设置，默认是60s。

```objc
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
request.timeoutInterval = 20;  // 设置整体超时时间为20秒
```

#### 设置上传进度回调

```objc
typedef void(^EMASCurlUploadProgressUpdateBlock)(NSURLRequest * _Nonnull request,
                                         int64_t bytesSent,
                                         int64_t totalBytesSent,
                                         int64_t totalBytesExpectedToSend);

+ (void)setUploadProgressUpdateBlockForRequest:(nonnull NSMutableURLRequest *)request uploadProgressUpdateBlock:(nonnull EMASCurlUploadProgressUpdateBlock)uploadProgressUpdateBlock;
```

由于`NSURLProtocol`并未提供合适的机制来提供上传进度的跟踪，EMASCurl提供了一个额外的上传进度处理方式。您可以为每个请求设置上传进度回调。

例如：

```objc
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
[EMASCurlProtocol setUploadProgressUpdateBlockForRequest:request uploadProgressUpdateBlock:^(NSURLRequest * _Nonnull request, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
    NSLog(@"上传进度: 已发送 %lld / 总共 %lld 字节", totalBytesSent, totalBytesExpectedToSend);
}];
```

#### 设置性能指标回调

##### 综合性能指标回调

EMASCurl提供基本等价于`URLSessionTaskTransactionMetrics`的完整性能指标：

```objc
/// 综合性能指标数据结构
@interface EMASCurlTransactionMetrics : NSObject
// 时间戳信息
@property (nonatomic, strong, nullable) NSDate *fetchStartDate;
@property (nonatomic, strong, nullable) NSDate *domainLookupStartDate;
@property (nonatomic, strong, nullable) NSDate *domainLookupEndDate;
@property (nonatomic, strong, nullable) NSDate *connectStartDate;
@property (nonatomic, strong, nullable) NSDate *secureConnectionStartDate;
@property (nonatomic, strong, nullable) NSDate *secureConnectionEndDate;
@property (nonatomic, strong, nullable) NSDate *connectEndDate;
@property (nonatomic, strong, nullable) NSDate *requestStartDate;
@property (nonatomic, strong, nullable) NSDate *requestEndDate;
@property (nonatomic, strong, nullable) NSDate *responseStartDate;
@property (nonatomic, strong, nullable) NSDate *responseEndDate;

// 网络信息
@property (nonatomic, copy, nullable) NSString *networkProtocolName;
@property (nonatomic, assign) BOOL proxyConnection;
@property (nonatomic, assign) BOOL reusedConnection;
@property (nonatomic, assign) NSInteger requestHeaderBytesSent;
@property (nonatomic, assign) NSInteger responseHeaderBytesReceived;
@property (nonatomic, copy, nullable) NSString *localAddress;
@property (nonatomic, assign) NSInteger localPort;
@property (nonatomic, copy, nullable) NSString *remoteAddress;
@property (nonatomic, assign) NSInteger remotePort;

// SSL/TLS信息（暂不支持，留空）
@property (nonatomic, copy, nullable) NSString *tlsProtocolVersion;
@property (nonatomic, copy, nullable) NSString *tlsCipherSuite;

@end
```

**使用综合性能指标回调示例：**

```objc
// 创建配置并设置性能指标回调
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.transactionMetricsObserver = ^(NSURLRequest * _Nonnull request, BOOL success, NSError * _Nullable error, EMASCurlTransactionMetrics * _Nonnull metrics) {
    if (!success) {
        NSLog(@"请求失败，URL: %@, 错误: %@", request.URL.absoluteString, error.localizedDescription);
        return;
    }

    NSLog(@"综合性能指标 [%@]:", request.URL.absoluteString);
    NSLog(@"获取开始时间: %@", metrics.fetchStartDate);
    NSLog(@"域名解析: %@ - %@", metrics.domainLookupStartDate, metrics.domainLookupEndDate);
    NSLog(@"连接建立: %@ - %@", metrics.connectStartDate, metrics.connectEndDate);
    NSLog(@"安全连接: %@ - %@", metrics.secureConnectionStartDate, metrics.secureConnectionEndDate);
    NSLog(@"请求处理: %@ - %@", metrics.requestStartDate, metrics.requestEndDate);
    NSLog(@"响应接收: %@ - %@", metrics.responseStartDate, metrics.responseEndDate);
    NSLog(@"协议: %@", metrics.networkProtocolName);
    NSLog(@"连接重用: %@", metrics.reusedConnection ? @"是" : @"否");
    NSLog(@"请求头字节: %ld, 响应头字节: %ld", (long)metrics.requestHeaderBytesSent, (long)metrics.responseHeaderBytesReceived);
    NSLog(@"地址: %@:%ld -> %@:%ld", metrics.localAddress, (long)metrics.localPort, metrics.remoteAddress, (long)metrics.remotePort);
    NSLog(@"TLS: %@ (%@)", metrics.tlsProtocolVersion, metrics.tlsCipherSuite);
};

// 应用配置到session
NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:config];
```


#### 开启调试日志

EMASCurl提供了多级别的日志系统，支持组件化的日志记录，便于调试和问题排查。

##### 设置日志级别

```objc
+ (void)setLogLevel:(EMASCurlLogLevel)logLevel;
+ (EMASCurlLogLevel)currentLogLevel;
```

EMASCurl支持以下日志级别：

- `EMASCurlLogLevelOff` (0): 禁用所有日志
- `EMASCurlLogLevelError` (1): 仅显示错误信息
- `EMASCurlLogLevelInfo` (2): 显示信息和错误级别日志
- `EMASCurlLogLevelDebug` (3): 显示所有日志，包括详细的调试信息和libcurl输出

例如：

```objc
// 设置为信息级别，显示错误和信息日志
[EMASCurlProtocol setLogLevel:EMASCurlLogLevelInfo];

// 获取当前日志级别
EMASCurlLogLevel currentLevel = [EMASCurlProtocol currentLogLevel];
NSLog(@"当前日志级别: %ld", (long)currentLevel);

// 设置为调试级别，显示所有日志
[EMASCurlProtocol setLogLevel:EMASCurlLogLevelDebug];
```

##### 组件化日志

EMASCurl使用组件化的日志记录，每个日志消息都会标明来源组件，便于问题定位：

- `[EC-Protocol]`: 主协议处理相关
- `[EC-Request]`: 请求验证和过滤相关
- `[EC-DNS]`: DNS解析相关
- `[EC-SSL]`: SSL/TLS配置相关
- `[EC-Cache]`: 响应缓存相关
- `[EC-Response]`: 响应处理相关
- `[EC-Performance]`: 性能指标相关
- `[EC-Proxy]`: 代理配置相关
- `[EC-libcurl]`: libcurl详细输出
- `[EC-Manager]`: 连接管理相关

日志输出格式：
```
[时间戳] [级别] [组件] 消息内容
```

示例输出：
```
[2024-12-27 10:30:15.123] [INFO] [EC-Protocol] Starting request for URL: https://example.com
[2024-12-27 10:30:15.124] [DEBUG] [EC-DNS] Resolved example.com to IPs: 93.184.216.34
[2024-12-27 10:30:15.125] [INFO] [EC-SSL] Certificate validation enabled
[2024-12-27 10:30:15.200] [INFO] [EC-Manager] Transfer completed successfully for URL: https://example.com (HTTP 200)
```

##### 设置自定义日志处理器

EMASCurl支持将日志输出到自定义组件，而不仅限于控制台。您可以通过设置自定义日志处理器，将日志重定向到文件、远程服务器或自定义UI界面。

```objc
+ (void)setLogHandler:(nullable EMASCurlLogHandlerBlock)handler;
```

日志处理器Block定义：
```objc
typedef void(^EMASCurlLogHandlerBlock)(EMASCurlLogLevel level, NSString *component, NSString *message);
```

使用示例：

```objc
// 示例1：将日志写入文件
[EMASCurlProtocol setLogHandler:^(EMASCurlLogLevel level, NSString *component, NSString *message) {
    // 构建日志字符串
    NSString *levelString = @"INFO";
    if (level == EMASCurlLogLevelError) {
        levelString = @"ERROR";
    } else if (level == EMASCurlLogLevelDebug) {
        levelString = @"DEBUG";
    }

    NSString *logEntry = [NSString stringWithFormat:@"[%@] [%@] %@\n", levelString, component, message];

    // 写入日志文件
    [MyLogger appendToFile:logEntry];
}];

// 示例2：发送到远程日志服务
[EMASCurlProtocol setLogHandler:^(EMASCurlLogLevel level, NSString *component, NSString *message) {
    if (level == EMASCurlLogLevelError) {
        [MyAnalytics reportError:message component:component];
    }
}];

// 示例3：显示在自定义UI
[EMASCurlProtocol setLogHandler:^(EMASCurlLogLevel level, NSString *component, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [MyDebugConsole appendLog:message level:level component:component];
    });
}];

// 恢复默认NSLog行为
[EMASCurlProtocol setLogHandler:nil];
```

**注意事项：**
- 如果不设置自定义处理器，日志将默认输出到控制台（NSLog），保持向后兼容
- 日志处理器会在日志产生的线程上调用，如需UI操作请切换到主线程
- 传入 `nil` 可恢复默认 NSLog 行为
- 自定义处理器会接收到原始的日志级别、组件名称和消息内容，您可以自由格式化输出

#### 设置请求拦截域名白名单和黑名单

EMASCurl允许您设置域名白名单和黑名单来控制哪些请求会被拦截处理：
- 处理请求时，EMASCurl会先检查黑名单，再检查白名单
- 白名单：只拦截白名单中的域名请求
- 黑名单：不拦截黑名单中的域名请求

例如：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];

// 只拦截这些域名的请求
config.domainWhiteList = @[@"example.com", @"api.example.com"];

// 不拦截这些域名的请求
config.domainBlackList = @[@"analytics.example.com"];

// 应用配置
NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:config];
```

#### 设置Gzip压缩

EMASCurl默认开启内部Gzip压缩。开启后，请求的header中会自动添加`Accept-Encoding: deflate, gzip`，并自动解压响应内容。若关闭，则需要自行处理请求/响应中的gzip字段。

例如：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.enableBuiltInGzip = NO;  // 关闭内置Gzip支持
// 或
config.enableBuiltInGzip = YES; // 启用（默认）
```

#### 设置内部重定向支持

EMASCurl可以配置是否自动处理HTTP重定向（如301、302等状态码）。

例如：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.enableBuiltInRedirection = YES;  // 开启内部重定向支持（默认）
// 或
config.enableBuiltInRedirection = NO;   // 关闭
```

#### 设置公钥固定 (Public Key Pinning)

设置用于公钥固定(Public Key Pinning)的公钥文件路径。libcurl 会使用此文件中的公钥信息来验证服务器证书链中的公钥。

**要求公钥 PEM 文件的结构：**
1.  公钥 PEM 文件必须包含一个有效的公钥信息，格式为 PEM 格式，即包含 `-----BEGIN PUBLIC KEY-----` 和 `-----END PUBLIC KEY-----` 区块，内容为公钥的 base64 编码。
2.  文件内容示例：
    ```
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...
    ...base64 data...
    -----END PUBLIC KEY-----
    ```

如果用户仅持有 PEM 格式的证书文件，而不是单独的公钥 PEM 文件，可以通过以下命令从证书中提取公钥：

使用 OpenSSL 工具：
```bash
openssl x509 -in your-cert.pem -pubkey -noout -out publickey.pem
```
该命令会从 PEM 证书文件（`your-cert.pem`）中提取公钥，并将公钥保存到 `publickey.pem` 文件中。生成的公钥文件应符合上述结构要求，可以直接用于公钥固定。

例如：

```objc
NSString *publicKeyPath = [[NSBundle mainBundle] pathForResource:@"my_public_key" ofType:@"pem"];

EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.publicKeyPinningKeyPath = publicKeyPath;
```

#### 设置证书校验

设置是否开启 SSL 证书校验。默认情况下，证书校验是开启的 (`YES`)。

- 当设置为 `YES` 时，libcurl 会验证服务器证书的有效性，包括证书链、有效期等。
- 当设置为 `NO` 时，libcurl 将不执行证书校验，这通常仅用于测试或连接到使用自签名证书且无法提供 CA 证书的服务器。**在生产环境中关闭证书校验会带来安全风险，请谨慎使用。**

例如：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.certificateValidationEnabled = NO;  // 关闭证书校验
// 或
config.certificateValidationEnabled = YES; // 开启证书校验 (默认行为)
```

#### 设置域名校验

设置是否开启 SSL 证书中的域名校验。默认情况下，域名校验是开启的 (`YES`)。

- 当设置为 `YES` 时，libcurl 会验证服务器证书中的 Common Name (CN) 或 Subject Alternative Name (SAN) 是否与请求的域名匹配。
- 当设置为 `NO` 时，libcurl 将不执行域名校验。**在生产环境中关闭域名校验会带来安全风险，可能导致中间人攻击，请谨慎使用。**

例如：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.domainNameVerificationEnabled = NO;  // 关闭域名校验
// 或
config.domainNameVerificationEnabled = YES; // 开启域名校验 (默认行为)
```

#### 设置手动代理服务器

设置手动代理服务器。设置后会覆盖系统代理设置。

代理字符串格式：`[protocol://]user:password@host[:port]`

例如: `http://user:pass@myproxy.com:8080` 或 `socks5://127.0.0.1:1080`

例如：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];

// 设置HTTP代理（当 proxyServer 非空时，总是使用该代理）
config.proxyServer = @"http://user:pass@proxy.example.com:8080";

// 或设置SOCKS5代理
// config.proxyServer = @"socks5://192.168.1.100:1080";

// 清空以回退到系统代理
// config.proxyServer = nil;
```

#### 设置HTTP缓存

设置是否启用HTTP缓存。EMASCurl默认启用HTTP缓存。

缓存功能特性包括：
1. 自动缓存可缓存的HTTP响应
2. 支持304 Not Modified响应处理
3. 遵循Cache-Control头信息控制缓存行为
4. 自动管理和清理过期缓存
5. 缓存使用`[NSURLCache sharedURLCache]`

例如：

```objc
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
config.cacheEnabled = YES;  // 启用HTTP缓存（默认）
// 或
config.cacheEnabled = NO;   // 禁用HTTP缓存
```

### EMASCurlConfiguration 完整属性参考

EMASCurlConfiguration 提供了所有网络配置选项的集中管理。以下是完整的属性列表：

| 属性 | 类型 | 默认值 | 说明 |
|:---|:---|:---|:---|
| **核心网络设置** | | | |
| `httpVersion` | HTTPVersion | HTTP2 | HTTP协议版本（HTTP1/HTTP2） |
| `connectTimeoutInterval` | NSTimeInterval | 2.5 | 连接超时时间（秒） |
| `enableBuiltInGzip` | BOOL | YES | 是否启用内置gzip压缩 |
| `enableBuiltInRedirection` | BOOL | YES | 是否启用内置重定向处理 |
| **DNS和代理** | | | |
| `dnsResolver` | Class | nil | 自定义DNS解析器类 |
| `proxyServer` | NSString | nil | 代理服务器URL（非空时总是使用该代理） |
| **安全设置** | | | |
| `caFilePath` | NSString | nil | CA证书文件路径 |
| `publicKeyPinningKeyPath` | NSString | nil | 公钥固定文件路径 |
| `certificateValidationEnabled` | BOOL | YES | 是否启用证书验证 |
| `domainNameVerificationEnabled` | BOOL | YES | 是否启用域名验证 |
| **域名过滤** | | | |
| `domainWhiteList` | NSArray | nil | 域名白名单 |
| `domainBlackList` | NSArray | nil | 域名黑名单 |
| **缓存** | | | |
| `cacheEnabled` | BOOL | YES | 是否启用HTTP缓存 |
| **性能监控** | | | |
| `transactionMetricsObserver` | Block | nil | 性能指标回调块 |

**使用示例：**

```objc
// 创建完整配置
EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];

// 网络设置
config.connectTimeoutInterval = 5.0;
config.enableBuiltInGzip = YES;
config.enableBuiltInRedirection = YES;

// DNS解析
config.dnsResolver = [MyDNSResolver class];

// 安全设置
config.certificateValidationEnabled = YES;
config.domainNameVerificationEnabled = YES;

// 域名过滤
config.domainWhiteList = @[@"api.example.com"];
config.domainBlackList = @[@"tracking.example.com"];

// 缓存
config.cacheEnabled = YES;

// 性能监控
config.transactionMetricsObserver = ^(NSURLRequest *request, BOOL success,
                                     NSError *error, EMASCurlTransactionMetrics *metrics) {
    // 处理性能指标
};

// 应用配置
NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:config];
```

## EMASLocalProxy - 统一代理方案

### 已知限制

- iOS 17 及以上：全场景支持
- iOS 17 以下：WKWebView 不支持代理
- iOS 17 以下：NSURLSession 仅 HTTPS 走代理，HTTP 明文请求不走代理

### 简介

EMASLocalProxy 是阿里云 EMAS 团队提供的本地 HTTPS 代理服务，为 iOS 17+ 的 WKWebView 提供统一代理与 HTTPDNS 能力。本 README 仅保留 WKWebView 相关指引；NSURLSession 场景推荐使用 EMASCurl。

- **WKWebView 代理**：在 iOS 17.0+ 通过 proxyConfigurations 支持 WKWebView
- **HTTPDNS域名解析**：无缝集成阿里云 HTTPDNS 服务
- **现代API支持**：使用 iOS 17.0+ proxyConfigurations API
- **简化配置**：无需复杂的接入配置
- **生产级稳定性**：基于 Network framework 的可靠实现

### 从CocoaPods引入依赖

在您的 `Podfile` 文件中添加 EMASLocalProxy 依赖：

```ruby
source 'https://github.com/aliyun/aliyun-specs.git'

target 'yourAppTarget' do
    use_framework!

    pod 'EMASLocalProxy', 'x.x.x'
end
```

当前最新版本: 1.4.2

### WKWebView集成

仅在 iOS 17.0+ 支持通过 proxyConfigurations 配置代理；低于 iOS 17 不支持 WKWebView 代理。

WKWebView 的代理配置相对简单，因为 WebView 通常不会在应用启动时立即加载：

```objc
#import <EMASLocalProxy/EMASLocalHttpProxy.h>
#import <WebKit/WebKit.h>

- (void)setupWebViewWithProxy {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];

    // EMASLocalProxy 会内部检查系统版本，iOS 17 以下会返回 NO
    BOOL success = [EMASLocalHttpProxy installIntoWebViewConfiguration:config];
    NSLog(@"WebView代理配置: %@", success ? @"成功" : @"失败，使用系统网络");

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];

    // 加载网页
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}
```

### 与HTTPDNS配合使用

EMASLocalProxy 可以与阿里云 HTTPDNS 服务无缝集成，提供自定义域名解析能力：

```objc
#import <AlicloudHttpDNS/AlicloudHttpDNS.h>

// 配置DNS解析器
[EMASLocalHttpProxy setDNSResolverBlock:^NSArray<NSString *> * _Nullable(NSString * _Nonnull hostname) {
    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
    HttpdnsResult *result = [httpdns resolveHostSyncNonBlocking:hostname byIpType:HttpdnsQueryIPTypeBoth];

    if (result && (result.hasIpv4Address || result.hasIpv6Address)) {
        NSMutableArray<NSString *> *allIPs = [NSMutableArray array];
        if (result.hasIpv4Address) {
            [allIPs addObjectsFromArray:result.ips];
        }
        if (result.hasIpv6Address) {
            [allIPs addObjectsFromArray:result.ipv6s];
        }
        NSLog(@"HTTPDNS解析成功，域名: %@, IP: %@", hostname, allIPs);
        return allIPs;
    }

    NSLog(@"HTTPDNS解析失败，域名: %@", hostname);
    return nil;
}];
```

### 调试和日志

EMASLocalProxy 提供了完善的日志系统，便于开发和调试：

```objc
// 设置日志级别
typedef NS_ENUM(NSInteger, EMASLocalHttpProxyLogLevel) {
    EMASLocalHttpProxyLogLevelNone = 0,   // 关闭日志
    EMASLocalHttpProxyLogLevelError = 1,  // 仅错误日志
    EMASLocalHttpProxyLogLevelInfo = 2,   // 信息和错误日志
    EMASLocalHttpProxyLogLevelDebug = 3   // 所有日志（包括详细调试信息）
};

// 开启调试日志
[EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelDebug];
```

#### 自定义日志处理器

EMASLocalProxy支持将日志输出到自定义组件，例如文件、远程服务器或自定义UI界面：

```objc
// 设置自定义日志处理器
[EMASLocalHttpProxy setLogHandler:^(EMASLocalHttpProxyLogLevel level, NSString *component, NSString *message) {
    // 自定义处理逻辑
    NSString *levelString = @"INFO";
    if (level == EMASLocalHttpProxyLogLevelError) {
        levelString = @"ERROR";
    } else if (level == EMASLocalHttpProxyLogLevelDebug) {
        levelString = @"DEBUG";
    }

    NSString *logEntry = [NSString stringWithFormat:@"[%@] [%@] %@", levelString, component, message];

    // 写入文件或发送到远程服务
    [MyLogger writeLog:logEntry];
}];

// 恢复默认NSLog行为
[EMASLocalHttpProxy setLogHandler:nil];
```

**注意事项：**
- 如果不设置自定义处理器，日志将默认输出到控制台（NSLog）
- 日志处理器会在日志产生的线程上调用，如需UI操作请切换到主线程
- 传入 `nil` 可恢复默认 NSLog 行为

## License

- Apache 2.0

## 联系我们

- [阿里云HTTPDNS官方文档中心](https://www.aliyun.com/product/httpdns#Docs)
- 阿里云EMAS开发交流钉钉群：35248489
