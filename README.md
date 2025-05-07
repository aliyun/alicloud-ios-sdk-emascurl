# EMASCurl

[![GitHub version](https://badge.fury.io/gh/aliyun%2Falicloud-ios-sdk-emascurl.git.svg)](https://badge.fury.io/gh/aliyun%2Falicloud-ios-sdk-emascurl.git)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)

EMASCurl是阿里云EMAS团队提供的基于[libcurl](https://github.com/curl/curl)的iOS平台网络库框架，能够与阿里云[HTTPDNS](https://www.aliyun.com/product/httpdns)配合使用，以降低iOS开发者接入[HTTPDNS](https://www.aliyun.com/product/httpdns)的门槛。

## 目录
- [EMASCurl](#emascurl)
  - [目录](#目录)
  - [最新版本](#最新版本)
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
    - [开启调试日志](#开启调试日志)
    - [设置请求拦截域名白名单和黑名单](#设置请求拦截域名白名单和黑名单)
    - [设置Gzip压缩](#设置gzip压缩)
    - [设置内部重定向支持](#设置内部重定向支持)
    - [设置公钥固定 (Public Key Pinning)](#设置公钥固定-public-key-pinning)
    - [设置手动代理服务器](#设置手动代理服务器)
  - [使用EMASCurlWeb](#使用emascurlweb)
    - [EMASCurlWeb简介](#emascurlweb简介)
    - [从CocoaPods引入EMASCurlWeb依赖](#从cocoapods引入emascurlweb依赖)
    - [配置WKWebView](#配置wkwebview)
    - [完整的接入示例](#完整的接入示例)
    - [与HTTPDNS在WebView中配合使用](#与httpdns在webview中配合使用)
    - [Cookie同步管理](#cookie同步管理)
    - [内部重定向处理](#内部重定向处理)
    - [响应缓存支持](#响应缓存支持)
    - [开启EMASCurlWeb调试日志](#开启emascurlweb调试日志)
  - [License](#license)
  - [联系我们](#联系我们)

## 最新版本

- 当前版本：1.2.0

## 快速入门

### 从CocoaPods引入依赖

在您的`Podfile`文件中添加如下依赖：

```ruby
source 'https://github.com/aliyun/aliyun-specs.git'

target 'yourAppTarget' do
    use_framework!

    pod 'EMASCurl', 'x.x.x'
end
```
在您的Terminal中进入`Podfile`所在目录，执行以下命令安装依赖：

```shell
pod install --repo-update
```

### 使用EMASCurl发送网络请求

首先，为您的`NSURLSessionConfiguration`注册EMASCurl实现。

```objc
NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:config];
```

之后，EMASCurl可以拦截此`NSURLSessionConfiguration`创建的`NSURLSession`发起的请求。

```objc
NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:[NSOperationQueue mainQueue]];

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

## 构建EMASCurl

本章节介绍如何使用本仓库本地构建EMASCurl `xcframework`。

### 构建工具安装

构建过程中需要使用`git`克隆代码、使用`automake`、`autoconf`、`libtool`、`pkg-config`等构建工具、使用`gem`、`ruby`、`xcodeproj`等工具，请您确认这些命令行工具已经安装在本机。如果尚未安装，请参考以下安装命令：

```shell
brew install automake autoconf libtool pkg-config
brew install ruby
gem install xcodeproj
```

### 拉取子模块

本仓库以`submodule`的形式管理依赖的仓库，在克隆后需要手动拉取子模块。

```shell
git submodule update --init --recursive --progress
```

所依赖的子模块版本信息如下：

| 依赖仓库         | 版本        |
|:-----------------|:------------|
| curl             | curl-8_10_1 |
| nghttp2         | v1.64.0     |

### 构建libcurl.xcframework

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

## 集成EMASCurl

本章节介绍如何将EMASCurl添加到您的应用中。

我们提供了CocoaPods引入依赖和本地手动集成两种方式，推荐工程使用CocoaPods管理依赖。

### CocoaPods引入依赖

#### 指定Master仓库和阿里云仓库

EMASCurl和其他EMAS产品的iOS SDK，都是发布到阿里云EMAS官方维护的GitHub仓库中，因此，您需要在您的`Podfile`文件中包含该仓库地址。

```ruby
source 'https://github.com/aliyun/aliyun-specs.git'
```

#### 添加依赖

为您需要依赖EMASCurl的target添加如下依赖。

```ruby
use_framework!

pod 'EMASCurl', 'x.x.x'
```

#### 安装依赖

在您的Terminal中进入`Podfile`所在目录，执行以下命令安装依赖。

```shell
pod install --repo-update
```

### 本地手动集成依赖

#### 将framework文件添加到工程中

您需要首先按照**EMASCurl构建**的步骤在本地构建出**EMASCurl.xcframework**，然后在Xcode工程项目中（`Build Phases` -> `Link Binary With Libraries`）添加对于**EMASCurl.xcframework**的依赖。

#### 添加Linker Flags

EMASCurl会使用`zlib`进行HTTP压缩与解压，因此您需要为应用的TARGETS -> Build Settings -> Linking -> Other Linker Flags添加上`-lz`与`-ObjC`。

#### 添加CA证书文件路径（如果使用自签名证书）

如果您使用自签名证书，还需将CA证书文件路径设置到EMASCurl中，具体请参考[使用EMASCurl](#使用emascurl)章节中的相关内容。

## 使用EMASCurl

### 开启EMASCurl拦截

目前EMASCurl有两种开启方式，第一种方式是拦截指定`NSURLSessionConfiguration`创建的`NSURLSession`发起的请求，第二种方式是拦截全局的`sharedSession`发起的请求。

#### 拦截`NSURLSessionConfiguration`

```objc
+ (void)installIntoSessionConfiguration:(nonnull NSURLSessionConfiguration *)sessionConfiguration;
```

首先，为您的`NSURLSessionConfiguration`安装EMASCurl。

```objc
NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
[EMASCurlProtocol installIntoSessionConfiguration:config];
```

之后，EMASCurl可以拦截此`NSURLSessionConfiguration`创建的`NSURLSession`发起的请求。

```objc
NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:[NSOperationQueue mainQueue]];

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

#### 拦截`sharedSession`

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

### 与HTTPDNS配合使用

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

然后调用以下方法为EMASCurl设置DNS解析器：

```objc
+ (void)setDNSResolver:(nonnull Class<EMASCurlProtocolDNSResolver>)dnsResolver;
```

例如：

```objc
[EMASCurlProtocol setDNSResolver:[MyDNSResolver class]];
```

### 选择HTTP版本

```objc
+ (void)setHTTPVersion:(HTTPVersion)version;
```

EMASCurl默认使用HTTP2版本，更高版本会包含低版本的能力。需要注意的是，HTTP3需要特殊的编译方式支持，且会引入更大的包体积，具体请参考完整的文档。

**HTTP1**: 使用HTTP1.1
**HTTP2**: 首先尝试使用HTTP2，如果与服务器的HTTP2协商失败，则会退回到HTTP1.1

### 设置CA证书文件路径

```objc
+ (void)setSelfSignedCAFilePath:(nonnull NSString *)selfSignedCAFilePath;
```

如果您的服务器使用自签名证书，您需要设置CA证书文件的路径，以确保EMASCurl能够正确验证SSL/TLS连接。

例如：

```objc
NSString *caFilePath = [[NSBundle mainBundle] pathForResource:@"my_ca" ofType:@"pem"];
[EMASCurlProtocol setSelfSignedCAFilePath:caFilePath];
```

### 设置Cookie存储

```objc
+ (void)setBuiltInCookieStorageEnabled:(BOOL)enabled;
```

EMASCurl默认开启内部Cookie存储功能，但只支持到[RFC 6265]标准。如果您选择关闭内置Cookie存储，在依赖cookie能力时，需要自行处理请求/响应中的cookie字段。

### 设置连接超时

```objc
+ (void)setConnectTimeoutIntervalForRequest:(nonnull NSMutableURLRequest *)request connectTimeoutInterval:(NSTimeInterval)connectTimeoutInSeconds;
```

`NSURLSession`未提供设置连接超时的方式，因此EMASCurl单独提供了此功能。对于请求的整体超时时间，请直接配置`NSURLRequest`中的`timeoutInterval`进行设置，默认是60s。

例如：

```objc
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
//设置整体超时时间为20s
request.timeoutInterval = 20;
//设置连接超时时间为10s
[EMASCurlProtocol setConnectTimeoutIntervalForRequest:request connectTimeoutInterval:10.0];
```

### 设置上传进度回调

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

### 设置性能指标回调

```objc
typedef void(^EMASCurlMetricsObserverBlock)(NSURLRequest * _Nonnull request,
                                   BOOL success,
                                   NSError * _Nullable error,
                                   double nameLookUpTimeMS,
                                   double connectTimeMs,
                                   double appConnectTimeMs,
                                   double preTransferTimeMs,
                                   double startTransferTimeMs,
                                   double totalTimeMs);

+ (void)setMetricsObserverBlockForRequest:(nonnull NSMutableURLRequest *)request metricsObserverBlock:(nonnull EMASCurlMetricsObserverBlock)metricsObserverBlock;
```

性能指标回调参数说明：
- `request`: 发起请求使用的请求实例
- `success`: 请求是否成功
- `error`: 如果请求失败，包含错误信息
- `nameLookUpTimeMS`: DNS解析耗时，单位毫秒
- `connectTimeMs`: TCP连接耗时，单位毫秒
- `appConnectTimeMs`: SSL/TLS握手耗时，单位毫秒
- `preTransferTimeMs`: 从开始到传输前准备完成的耗时，单位毫秒
- `startTransferTimeMs`: 从开始到收到第一个字节的耗时，单位毫秒
- `totalTimeMs`: 整个请求的总耗时，单位毫秒

网络请求性能指标回调，可以帮助您监控请求的各项耗时指标。

例如：

```objc
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
[EMASCurlProtocol setMetricsObserverBlockForRequest:request metricsObserverBlock:^(NSURLRequest * _Nonnull request, BOOL success, NSError * _Nullable error, double nameLookUpTimeMS, double connectTimeMs, double appConnectTimeMs, double preTransferTimeMs, double startTransferTimeMs, double totalTimeMs) {
    if (!success) {
        NSLog(@"请求失败，错误信息: %@", error.localizedDescription);
        return;
    }
    NSLog(@"性能指标:");
    NSLog(@"DNS解析耗时: %.2f ms", nameLookUpTimeMS);
    NSLog(@"TCP连接耗时: %.2f ms", connectTimeMs);
    NSLog(@"SSL/TLS握手耗时: %.2f ms", appConnectTimeMs);
    NSLog(@"传输前准备耗时: %.2f ms", preTransferTimeMs);
    NSLog(@"收到第一个字节耗时: %.2f ms", startTransferTimeMs);
    NSLog(@"总耗时: %.2f ms", totalTimeMs);
}];
```

### 开启调试日志

```objc
+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled;
```

开启后会打印出日志记录，便于调试。

例如：

```objc
[EMASCurlProtocol setDebugLogEnabled:YES];
```

### 设置请求拦截域名白名单和黑名单

```objc
+ (void)setHijackDomainWhiteList:(nullable NSArray<NSString *> *)domainWhiteList;
+ (void)setHijackDomainBlackList:(nullable NSArray<NSString *> *)domainBlackList;
```

EMASCurl允许您设置域名白名单和黑名单来控制哪些请求会被拦截处理：
- 处理请求时，EMASCurl会先检查黑名单，再检查白名单
- 白名单：只拦截白名单中的域名请求
- 黑名单：不拦截黑名单中的域名请求
- 传入nil时，会清除相应的名单

例如：

```objc
// 只拦截这些域名的请求
[EMASCurlProtocol setHijackDomainWhiteList:@[@"example.com", @"api.example.com"]];

// 不拦截这些域名的请求
[EMASCurlProtocol setHijackDomainBlackList:@[@"analytics.example.com"]];

// 清除白名单
[EMASCurlProtocol setHijackDomainWhiteList:nil];
```

### 设置Gzip压缩

```objc
+ (void)setBuiltInGzipEnabled:(BOOL)enabled;
```

EMASCurl默认开启内部Gzip压缩。开启后，请求的header中会自动添加`Accept-Encoding: deflate, gzip`，并自动解压响应内容。若关闭，则需要自行处理请求/响应中的gzip字段。

例如：

```objc
// 关闭内置Gzip支持
[EMASCurlProtocol setBuiltInGzipEnabled:NO];
```

### 设置内部重定向支持

```objc
+ (void)setBuiltInRedirectionEnabled:(BOOL)enabled;
```

EMASCurl可以配置是否自动处理HTTP重定向（如301、302等状态码）。

例如：

```objc
// 开启内部重定向支持
[EMASCurlProtocol setBuiltInRedirectionEnabled:YES];
```

### 设置公钥固定 (Public Key Pinning)

```objc
+ (void)setPublicKeyPinningKeyPath:(nullable NSString *)publicKeyPath;
```

设置用于公钥固定(Public Key Pinning)的公钥文件路径。libcurl 会使用此文件中的公钥信息来验证服务器证书链中的公钥。传入`nil`时，清除公钥固定设置。

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
[EMASCurlProtocol setPublicKeyPinningKeyPath:publicKeyPath];

// 清除公钥固定设置
// [EMASCurlProtocol setPublicKeyPinningKeyPath:nil];
```

### 设置手动代理服务器

```objc
+ (void)setManualProxyServer:(nullable NSString *)proxyServerURL;
```

设置手动代理服务器。设置后会覆盖系统代理设置。传入`nil`时，恢复使用系统代理设置。

代理字符串格式：`[protocol://]user:password@host[:port]`

例如: `http://user:pass@myproxy.com:8080` 或 `socks5://127.0.0.1:1080`

例如：

```objc
// 设置HTTP代理
[EMASCurlProtocol setManualProxyServer:@"http://user:pass@proxy.example.com:8080"];

// 设置SOCKS5代理
// [EMASCurlProtocol setManualProxyServer:@"socks5://192.168.1.100:1080"];

// 清除手动代理设置，恢复使用系统代理
// [EMASCurlProtocol setManualProxyServer:nil];
```

## 使用EMASCurlWeb

### EMASCurlWeb简介

**注意：本模块尚处于实验性质阶段。WebView涉及请求类型复杂，完全拦截网络请求难以做到通用方案，特别是Cookie处理、大文件上传等细节。本模块当前实现仅供参考，若业务已经实现或正在实现Hybrid预加载、本地加载等能力的情况下，可以参考本模块，实现符合业务自身需求的方案。**

EMASCurlWeb是EMASCurl的扩展模块，专门为WKWebView提供网络请求拦截和处理功能。通过使用WKURLSchemeHandler机制，EMASCurlWeb能够拦截WKWebView中的所有网络请求并通过EMASCurl进行处理，使得WebView中的网络请求也能够享受EMASCurl带来的以下好处：

- HTTP/2协议支持
- HTTPDNS域名解析
- 自定义CA证书支持
- 性能指标监控
- Cookie同步和管理
- 缓存管理

EMASCurlWeb适用于iOS 13.0及以上系统版本，主要解决以下问题：

1. 在WebView中使用HTTPDNS进行域名解析
2. 在WebView中支持HTTP/2协议
3. 在WebView和Native之间同步Cookie
4. 为WebView提供更灵活的缓存控制
5. 提供WebView网络请求的监控和拦截能力

### 从CocoaPods引入EMASCurlWeb依赖

在您的`Podfile`文件中添加EMASCurlWeb依赖：

```ruby
source 'https://github.com/aliyun/aliyun-specs.git'

target 'yourAppTarget' do
    use_framework!

    pod 'EMASCurl', 'x.x.x'
    pod 'EMASCurlWeb', 'x.x.x'
end
```

当前版本: 1.2.0-beta

### 配置WKWebView

使用EMASCurlWeb需要进行一些基本配置，主要包含以下步骤：

1. 创建和配置NSURLSessionConfiguration
2. 配置EMASCurlProtocol
3. 创建EMASCurlWebUrlSchemeHandler并绑定到WKWebViewConfiguration
4. 初始化EMASCurlWebContentLoader拦截功能
5. 配置Cookie管理
6. 创建并使用WKWebView

```objc
// 1. 创建和配置NSURLSessionConfiguration
NSURLSessionConfiguration *urlSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];

// 2. 配置EMASCurlProtocol
[EMASCurlProtocol setDebugLogEnabled:YES];
[EMASCurlProtocol installIntoSessionConfiguration:urlSessionConfig];

// 3. 创建WKWebViewConfiguration并配置EMASCurlWebUrlSchemeHandler
WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
EMASCurlWebUrlSchemeHandler *urlSchemeHandler = [[EMASCurlWebUrlSchemeHandler alloc] initWithSessionConfiguration:urlSessionConfig];
[configuration setURLSchemeHandler:urlSchemeHandler forURLScheme:@"http"];
[configuration setURLSchemeHandler:urlSchemeHandler forURLScheme:@"https"];

// 4. 初始化内容加载拦截
[EMASCurlWebContentLoader initializeInterception];

// 5. 启用Cookie处理
[configuration enableCookieHandler];

// 6. 创建并使用WKWebView
WKWebView *webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
[self.view addSubview:webView];

// 加载URL
NSURL *url = [NSURL URLWithString:@"https://example.com"];
NSURLRequest *request = [NSURLRequest requestWithURL:url];
[webView loadRequest:request];
```

### 完整的接入示例

以下是一个完整的控制器示例，展示了如何将EMASCurlWeb集成到您的应用中：

```objc
#import "WebViewDemoController.h"
#import <WebKit/WebKit.h>
#import <EMASCurl/EMASCurl.h>
#import <EMASCurlWeb/EMASCurlWeb.h>
#import <AlicloudHttpDNS/AlicloudHttpDNS.h>

// DNS解析器实现
@interface MyDNSResolver : NSObject <EMASCurlProtocolDNSResolver>
@end

@implementation MyDNSResolver
+ (NSString *)resolveDomain:(NSString *)domain {
    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
    HttpdnsResult* result = [httpdns resolveHostSyncNonBlocking:domain byIpType:HttpdnsQueryIPTypeBoth];
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
            NSLog(@"解析域名成功，域名: %@, 解析IP: %@", domain, combinedIPs);
            return combinedIPs;
        }
    }
    NSLog(@"解析域名失败，域名: %@", domain);
    return nil;
}
@end

@interface WebViewDemoController ()
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation WebViewDemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"EMASCurlWeb示例";

    // 添加刷新按钮到导航栏
    UIBarButtonItem *reloadButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                  target:self
                                                                                  action:@selector(reloadWebView)];
    self.navigationItem.rightBarButtonItem = reloadButton;

    // 1. 创建WKWebView配置
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];

    // 2. 配置URLSession和EMASCurl
    NSURLSessionConfiguration *urlSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol setBuiltInRedirectionEnabled:NO]; // 让WebView处理重定向
    [EMASCurlProtocol setDNSResolver:[MyDNSResolver class]]; // 设置DNS解析器
    [EMASCurlProtocol installIntoSessionConfiguration:urlSessionConfig];

    // 3. 配置EMASCurlWeb
    EMASCurlWebUrlSchemeHandler *urlSchemeHandler = [[EMASCurlWebUrlSchemeHandler alloc] initWithSessionConfiguration:urlSessionConfig];
    [configuration setURLSchemeHandler:urlSchemeHandler forURLScheme:@"http"];
    [configuration setURLSchemeHandler:urlSchemeHandler forURLScheme:@"https"];

    // 4. 初始化内容拦截
    [EMASCurlWebContentLoader initializeInterception];
    [EMASCurlWebContentLoader setDebugLogEnabled:YES];

    // 5. 启用Cookie处理
    [configuration enableCookieHandler];

    // 6. 创建并配置WebView
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    [self.view addSubview:self.webView];

    // 加载URL
    NSURL *url = [NSURL URLWithString:@"https://m.taobao.com"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

- (void)reloadWebView {
    [self.webView reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.webView.frame = self.view.safeAreaLayoutGuide.layoutFrame;
}

@end
```

### 与HTTPDNS在WebView中配合使用

EMASCurlWeb会自动使用EMASCurl配置的DNS解析器，您只需要正常配置EMASCurl的DNS解析器即可。

```objc
// 配置DNS解析器
[EMASCurlProtocol setDNSResolver:[MyDNSResolver class]];
```

配置完成后，WKWebView中的所有网络请求（包括主文档、AJAX请求、CSS、JavaScript、图片等资源）都会通过DNS解析器进行域名解析。

### Cookie同步管理

EMASCurlWeb提供了在Native和WebView之间自动同步Cookie的能力，解决了iOS平台Web和Native Cookie存储隔离的问题。当您使用`enableCookieHandler`方法时，会自动启用Cookie同步。

```objc
// 启用Cookie处理
[configuration enableCookieHandler];
```

Cookie同步机制实现了以下功能：

1. **服务器到WebView**：当EMASCurlWeb接收到HTTP响应中的Set-Cookie头时，会自动将Cookie同步到WKWebsiteDataStore
2. **JavaScript到Native**：通过注入JavaScript代码，监听document.cookie的变化，并将变更同步到NSHTTPCookieStorage

这确保了无论是通过HTTP响应还是JavaScript设置的Cookie，都能在WebView和Native环境之间共享。

### 内部重定向处理

在WebView中，处理重定向需要特别注意以维持导航历史和状态。EMASCurlWeb提供了专门的重定向处理机制：

```objc
// 关闭EMASCurl的内部重定向支持，由EMASCurlWeb处理
[EMASCurlProtocol setBuiltInRedirectionEnabled:NO];
```

当需要重定向时，EMASCurlWeb会：

1. 对于普通资源请求：自动处理重定向，无需额外配置
2. 对于主文档请求：通过WKWebView的loadRequest方法加载新URL，保持导航历史和状态

### 响应缓存支持

EMASCurlWeb实现了符合HTTP规范的缓存机制，支持ETag、Last-Modified、Cache-Control等HTTP缓存控制标头。

缓存功能特性包括：

1. 自动缓存可缓存的HTTP响应
2. 支持304 Not Modified响应处理
3. 遵循Cache-Control头信息控制缓存行为
4. 自动管理和清理过期缓存

缓存机制完全透明，无需额外配置，EMASCurlWeb会根据HTTP规范自动处理缓存逻辑。

### 开启EMASCurlWeb调试日志

EMASCurlWeb提供了独立的日志控制，可以单独开启或关闭：

```objc
// 开启EMASCurlWeb的调试日志
[EMASCurlWebContentLoader setDebugLogEnabled:YES];
```

开启调试日志后，EMASCurlWeb会输出网络请求的详细信息，包括URL、响应状态、缓存情况等，便于开发和调试。

## License

- Apache 2.0

## 联系我们

- [阿里云HTTPDNS官方文档中心](https://www.aliyun.com/product/httpdns#Docs)
- 阿里云EMAS开发交流钉钉群：35248489
