# EMASCurl

[![GitHub version](https://badge.fury.io/gh/aliyun%2Falicloud-ios-sdk-emascurl.git.svg)](https://badge.fury.io/gh/aliyun%2Falicloud-ios-sdk-emascurl.git)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)

EMASCurl是阿里云EMAS团队提供的基于[libcurl](https://github.com/curl/curl)的iOS平台网络库框架，能够与阿里云[HTTPDNS](https://www.aliyun.com/product/httpdns)配合使用，以降低iOS开发者接入[HTTPDNS](https://www.aliyun.com/product/httpdns)的门槛。

## 目录
- [最新版本](#最新版本)
- [快速入门](#快速入门)
- [构建EMASCurl](#构建emascurl)
- [集成EMASCurl](#集成emascurl)
  - [cocoapods引入依赖](#cocoapods引入依赖)
  - [本地手动集成依赖](#本地手动集成依赖)
- [使用EMASCurl](#使用emascurl)
  - [开启EMASCurl拦截](#开启emascurl拦截)
  - [与HTTPDNS配合使用](#与httpdns配合使用)
  - [选择HTTP版本](#选择http版本)
  - [开启调试日志](#开启调试日志)
- [License](#license)
- [联系我们](#联系我们)

## 最新版本

- 当前版本：1.0.2-http2-beta

## 快速入门

### 从cocoapods引入依赖

在您的Podfile文件中添加如下依赖：

```ruby
source 'https://github.com/aliyun/aliyun-specs.git'

target 'yourAppTarget' do
    use_framework!

    pod 'EMASCurl', 'x.x.x'
end
```
在您的Terminal中进入Podfile所在目录，执行以下命令安装依赖
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
        NSLog(@"Request failed due to error: %@", error.localizedDescription);
        return;
    }
    NSLog(@"Response : %@", response);
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"Response body: %@", body);
}];

[dataTask resume];
```

## 构建EMASCurl

本章节介绍如何使用本仓库本地构建EMASCurl xcframework。

### 构建工具安装

构建过程中需要使用git克隆代码、使用automake, autoconf, libtool, pkg-config等构建工具、使用gem, ruby, xcodeproj等工具，请您确认这些命令行工具已经安装在本机，如果尚未安装参考以下安装命令：

```shell
brew install automake autoconf libtool pkg-config
brew install ruby
gem install xcodeproj
```

### 拉取子模块

本仓库以submodule的形式管理依赖的仓库，在克隆后需要手动拉取子模块。

```shell
git submodule update --init --recursive --progress
```

所依赖的子模块版本信息如下：
| dependency repository     | version     |
|:---------|:---------|
| curl  | curl-8_10_1  |
| nghttp2  | v1.64.0  |

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

我们提供了cocoapods引入依赖和本地依赖两种集成方式，推荐工程使用cocoapods管理依赖。

### cocoapods引入依赖

#### 指定Master仓库和阿里云仓库

EMASCurl和其他EMAS产品的iOS SDK，都是发布到阿里云EMAS官方维护的github仓库中，因此，您需要在您的Podfile文件中包含该仓库地址。

```shell
source 'https://github.com/aliyun/aliyun-specs.git'
```

#### 添加依赖

为您需要依赖EMASCurl的target添加如下依赖。

```shell
use_framework!

pod 'EMASCurl', '1.0.2-http2-beta'
```

#### 安装依赖

在您的Terminal中进入Podfile所在目录，执行以下命令安装依赖。

```shell
pod install --repo-update
```

### 本地手动集成依赖

#### 将framework文件添加到工程中

您需要首先按照**EMASCurl构建**的步骤在本地构建出**EMASCurl.xcframework**，然后在xcode工程项目中(Build Phases -> Link Binary With Libraries)添加对于**EMASCurl.xcframework**的依赖。

#### 添加Linker Flags

EMASCurl会使用zlib进行HTTP压缩与解压，因此您需要为应用的TARGETS -> Build Settings -> Linking -> Other Linker Flags添加上`-lz`与`-ObjC`。

## 使用EMASCurl

### 开启EMASCurl拦截

目前EMASCurl有两种开启方式，第一种方式是拦截指定`NSURLSessionConfiguration`创建的`NSURLSession`发起的请求，第二种方式是拦截全局的`sharedSession`发起的请求。

#### 拦截`NSURLSessionConfiguration`

```objc
+ (void)installIntoSessionConfiguration:(NSURLSessionConfiguration*)sessionConfiguration;
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
        NSLog(@"Request failed due to error: %@", error.localizedDescription);
        return;
    }
    NSLog(@"Response : %@", response);
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"Response body: %@", body);
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
        NSLog(@"Request failed due to error: %@", error.localizedDescription);
        return;
    }
    NSLog(@"Response : %@", response);
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"Response body: %@", body);
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

+ (NSString *)resolveDomain:(NSString *)domain;

@end
```

例如：

```objc
@interface MyDNSResolver : NSObject <EMASCurlProtocolDNSResolver>

@end

@implementation MyDNSResolver

+ (NSString *)resolveDomain:(NSString *)domain {
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
```

然后调用以下方法为EMASCurl设置DNS解析器：

```objc
+ (void)setDNSResolver:(Class<EMASCurlProtocolDNSResolver>)resolver;
```

例如：

```objc
[EMASCurlProtocol setDNSResolver:[MyDNSResolver class]];
```

### 选择HTTP版本

```objc
+ (void)setHTTPVersion:(HTTPVersion)version;
```

目前提供HTTP1与HTTP2两种版本：

+ HTTP1: 使用HTTP1.1
+ HTTP2: 首先尝试使用HTTP2，如果与服务器的HTTP2协商失败，则会退回到HTTP1.1

### 开启调试日志

```objc
+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled;
```

开启后会打印出日志记录。

## License

- Apache 2.0

## 联系我们

- [阿里云HTTPDNS官方文档中心](https://www.aliyun.com/product/httpdns#Docs)
- 阿里云官方技术支持：[提交工单](https://workorder.console.aliyun.com/#/ticket/createIndex)
- 阿里云EMAS开发交流钉钉群：35248489