//
//  EMASCurlProtocol.h
//  EMASCurl
//
//  Created by xin yu on 2024/10/29.
//

#ifndef EMASCurlProtocol_h
#define EMASCurlProtocol_h

#import <Foundation/Foundation.h>

#define EMASCURL_SDK_VERSION @"1.3.0"

/// 提供一个便捷易用的DNS Hook机制，类似OKHTTP中的DNS配置
@protocol EMASCurlProtocolDNSResolver <NSObject>

/// 实现这个方法时，解析域名得到的多个IP通过','拼接，如 10.10.10.10,11.11.11.11,12.12.12.12。
/// 如果涉及IPv4和IPv6协议，无需特别区分，直接将IPv6的IP和IPv4的IP拼接到一起返回，EMASCurl会自行决策如何请求
///
/// param @domain 请求域名
/// return 解析后的IP地址，多个IP通过','拼接，如
///        10.10.10.10,11.11.11.11,12.12.12.12
///        10.10.10.10,5be8:dde9:7f0b:d5a7:bd01:b3be:9c69:573b,12.12.12.12,5be8:dde9:7f0b:d5a7:bd01:b3be:9c69:573b
///        返回nil时，EMASCurl会使用默认的DNS解析
+ (nullable NSString *)resolveDomain:(nonnull NSString *)domain;

@end


/// 由于`NSURLProtocol`并未提供合适的机制来提供上传进度的跟踪，我们提供一个额外的上传进度处理方式
///
/// param @request 发起请求使用的请求实例
/// param @bytesSent: 已发送的字节数
/// param @totalBytesSent: 已发送的总字节数
/// param @totalBytesExpectedToSend: 总字节数
typedef void(^EMASCurlUploadProgressUpdateBlock)(NSURLRequest * _Nonnull request,
                                         int64_t bytesSent,
                                         int64_t totalBytesSent,
                                         int64_t totalBytesExpectedToSend);

/// 网络请求性能指标回调
///
/// param @request 发起请求使用的请求实例
/// param @nameLookUpTimeMS DNS解析耗时，单位毫秒
/// param @connectTimeMs TCP连接耗时，单位毫秒
/// param @appConnectTimeMs SSL/TLS握手耗时，单位毫秒
/// param @preTransferTimeMs 从开始到传输前准备完成的耗时，单位毫秒
/// param @startTransferTimeMs 从开始到收到第一个字节的耗时，单位毫秒
/// param @totalTimeMs 整个请求的总耗时，单位毫秒
typedef void(^EMASCurlMetricsObserverBlock)(NSURLRequest * _Nonnull request,
                                   BOOL success,
                                   NSError * _Nullable error,
                                   double nameLookUpTimeMS,
                                   double connectTimeMs,
                                   double appConnectTimeMs,
                                   double preTransferTimeMs,
                                   double startTransferTimeMs,
                                   double totalTimeMs);


// HTTP版本，高版本一定包含支持低版本
typedef NS_ENUM(NSInteger, HTTPVersion) {
    HTTP1,
    HTTP2,
    HTTP3
};


@interface EMASCurlProtocol : NSURLProtocol

// 拦截使用自定义`NSURLSessionConfiguration`创建的session发起的requst
+ (void)installIntoSessionConfiguration:(nonnull NSURLSessionConfiguration *)sessionConfiguration;

// 拦截`sharedSession`发起的request
+ (void)registerCurlProtocol;

// 注销对`sharedSession`的拦截
+ (void)unregisterCurlProtocol;

// 设置支持的HTTP版本，默认HTTP2
// 更高版本一定包含低版本
// HTTP3需要特殊的编译方式支持，且会引入更大的包体积，参考完整的readme文档
+ (void)setHTTPVersion:(HTTPVersion)version;

// 设置是否开启内部Gzip压缩，开启后，请求的header中会自动添加`Accept-Encoding: deflate, gzip`，并自动解压
// 默认开启
// 若关闭，则依赖gzip能力时，需要自行处理请求/响应中的gzip字段
+ (void)setBuiltInGzipEnabled:(BOOL)enabled;

// 设置CA证书文件路径，在使用自签名证书做测试时使用
+ (void)setSelfSignedCAFilePath:(nonnull NSString *)selfSignedCAFilePath;

// 是否开启内部重定向支持
+ (void)setBuiltInRedirectionEnabled:(BOOL)enabled;

// 设置是否开启调试日志
+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled;

// 设置DNS解析器
+ (void)setDNSResolver:(nonnull Class<EMASCurlProtocolDNSResolver>)dnsResolver;

// 设置连接超时，单位秒
// `NSURLSession`未提供设置连接超时的方式，因此这里单独提供
// 对于请求的整体超时时间，请直接配置`NSURLRequest`中的`timeoutInterval`进行设置，默认是60s
+ (void)setConnectTimeoutIntervalForRequest:(nonnull NSMutableURLRequest *)request connectTimeoutInterval:(NSTimeInterval)connectTimeoutInSeconds;

// 设置上传进度回调
+ (void)setUploadProgressUpdateBlockForRequest:(nonnull NSMutableURLRequest *)request uploadProgressUpdateBlock:(nonnull EMASCurlUploadProgressUpdateBlock)uploadProgressUpdateBlock;

// 设置性能指标回调
+ (void)setMetricsObserverBlockForRequest:(nonnull NSMutableURLRequest *)request metricsObserverBlock:(nonnull EMASCurlMetricsObserverBlock)metricsObserverBlock;

// 设置拦截域名白名单，处理请求时，先检查黑名单，再检查白名单
// 只拦截白名单中的域名
// 传入nil时，清除白名单
+ (void)setHijackDomainWhiteList:(nullable NSArray<NSString *> *)domainWhiteList;

// 设置拦截域名黑名单，处理请求时，先检查黑名单，再检查白名单
// 不拦截黑名单中的域名
// 传入nil时，清除黑名单
+ (void)setHijackDomainBlackList:(nullable NSArray<NSString *> *)domainBlackList;

// 设置用于公钥固定(Public Key Pinning)的公钥文件路径。
// libcurl 会使用此文件中的公钥信息来验证服务器证书链中的公钥。
// 传入nil时，清除公钥固定设置。
//
// 要求公钥 PEM 文件的结构：
// 1. 公钥 PEM 文件必须包含一个有效的公钥信息，格式为 PEM 格式，
//    即包含 `-----BEGIN PUBLIC KEY-----` 和 `-----END PUBLIC KEY-----` 区块，内容为公钥的 base64 编码。
// 2. 文件内容示例：
//    -----BEGIN PUBLIC KEY-----
//    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...
//    ...base64 data...
//    -----END PUBLIC KEY-----
//
// 如果用户仅持有 PEM 格式的证书文件，而不是单独的公钥 PEM 文件，可以通过以下命令从证书中提取公钥：
//
//    使用 OpenSSL 工具：
//    ```bash
//    openssl x509 -in your-cert.pem -pubkey -noout -out publickey.pem
//    ```
//    该命令会从 PEM 证书文件（`your-cert.pem`）中提取公钥，并将公钥保存到 `publickey.pem` 文件中。
//    生成的公钥文件应符合上述结构要求，可以直接用于公钥固定。
+ (void)setPublicKeyPinningKeyPath:(nullable NSString *)publicKeyPath;

// 设置是否开启证书校验，默认开启
+ (void)setCertificateValidationEnabled:(BOOL)enabled;

// 设置是否开启域名校验，默认开启
+ (void)setDomainNameVerificationEnabled:(BOOL)enabled;

// 设置手动代理服务器。设置后会覆盖系统代理设置。
// 传入nil时，恢复使用系统代理设置。
// 代理字符串格式：[protocol://]user:password@host[:port]
// 例如: http://user:pass@myproxy.com:8080 或 socks5://127.0.0.1:1080
+ (void)setManualProxyServer:(nullable NSString *)proxyServerURL;

#pragma mark - HTTP缓存相关方法

// 设置是否启用HTTP缓存，默认启用
+ (void)setCacheEnabled:(BOOL)enabled;

@end

#endif /* EMASCurlProtocol_h */
