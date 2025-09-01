//
//  EMASCurlProtocol.h
//  EMASCurl
//
//  Created by xin yu on 2024/10/29.
//

#ifndef EMASCurlProtocol_h
#define EMASCurlProtocol_h

#import <Foundation/Foundation.h>
#import <EMASCurl/EMASCurlConfiguration.h>

#define EMASCURL_SDK_VERSION @"1.4.0"


// 日志级别枚举
typedef NS_ENUM(NSInteger, EMASCurlLogLevel) {
    EMASCurlLogLevelOff = 0,      // 禁用所有日志
    EMASCurlLogLevelError = 1,    // 仅错误信息
    EMASCurlLogLevelInfo = 2,     // 信息和错误
    EMASCurlLogLevelDebug = 3,    // 调试信息和以上所有，包括libcurl输出
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

// 设置是否开启调试日志 (保持向后兼容性)
+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled;

#pragma mark - 日志相关方法

// 设置全局日志级别
+ (void)setLogLevel:(EMASCurlLogLevel)logLevel;

// 获取当前日志级别
+ (EMASCurlLogLevel)currentLogLevel;

#pragma mark - 其他配置方法

// 设置DNS解析器
+ (void)setDNSResolver:(nonnull Class<EMASCurlProtocolDNSResolver>)dnsResolver;

// 设置连接超时，单位秒，默认2.5秒
// 影响所有未单独设置连接超时的请求
+ (void)setConnectTimeoutInterval:(NSTimeInterval)timeoutInterval;

// 设置连接超时，单位秒
// `NSURLSession`未提供设置连接超时的方式，因此这里单独提供
// 对于请求的整体超时时间，请直接配置`NSURLRequest`中的`timeoutInterval`进行设置，默认是60s
+ (void)setConnectTimeoutIntervalForRequest:(nonnull NSMutableURLRequest *)request connectTimeoutInterval:(NSTimeInterval)connectTimeoutInSeconds;

// 设置上传进度回调
+ (void)setUploadProgressUpdateBlockForRequest:(nonnull NSMutableURLRequest *)request uploadProgressUpdateBlock:(nonnull EMASCurlUploadProgressUpdateBlock)uploadProgressUpdateBlock;

/// 设置全局综合性能指标观察回调（推荐使用）
/// 提供等价于URLSessionTaskTransactionMetrics的完整性能指标
/// @param transactionMetricsObserverBlock 综合性能指标回调，传入nil清除回调
+ (void)setGlobalTransactionMetricsObserverBlock:(nullable EMASCurlTransactionMetricsObserverBlock)transactionMetricsObserverBlock;

/// 为指定请求设置性能指标观察回调（已废弃，请使用全局回调）
/// @param request 请求对象
/// @param metricsObserverBlock 性能指标回调
+ (void)setMetricsObserverBlockForRequest:(nonnull NSMutableURLRequest *)request metricsObserverBlock:(nonnull EMASCurlMetricsObserverBlock)metricsObserverBlock NS_DEPRECATED(10_0, 18_0, 10_0, 18_0, "请使用 setGlobalMetricsObserverBlock: 替代");

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

#pragma mark - Multi-Instance Configuration Support

@class EMASCurlConfiguration;

/**
 * 多实例配置支持分类
 * 允许不同的NSURLSession实例拥有独立的配置
 */
@interface EMASCurlProtocol (MultiInstance)

/**
 * 将EMASCurlProtocol安装到带有特定配置的session配置中
 * 每个session可以拥有自己的网络设置
 *
 * @param sessionConfig 要安装到的NSURLSessionConfiguration
 * @param curlConfig 此session使用的EMASCurlConfiguration
 */
+ (void)installIntoSessionConfiguration:(nonnull NSURLSessionConfiguration *)sessionConfig
                       withConfiguration:(nonnull EMASCurlConfiguration *)curlConfig;

/**
 * 获取当前默认配置
 *
 * @return 默认配置
 */
+ (nonnull EMASCurlConfiguration *)defaultConfiguration;

@end

#endif /* EMASCurlProtocol_h */
