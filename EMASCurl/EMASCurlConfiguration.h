//
//  EMASCurlConfiguration.h
//  EMASCurl
//
//  Created by EMASCurl on 2025/01/02.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


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


/// 综合性能指标数据结构（类似于URLSessionTaskTransactionMetrics）
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
@property (nonatomic, assign) NSInteger requestBodyBytesSent;
@property (nonatomic, assign) NSInteger responseHeaderBytesReceived;
@property (nonatomic, assign) NSInteger responseBodyBytesReceived;
@property (nonatomic, copy, nullable) NSString *localAddress;
@property (nonatomic, assign) NSInteger localPort;
@property (nonatomic, copy, nullable) NSString *remoteAddress;
@property (nonatomic, assign) NSInteger remotePort;

// SSL/TLS信息 (暂不支持，留空)
@property (nonatomic, copy, nullable) NSString *tlsProtocolVersion;
@property (nonatomic, copy, nullable) NSString *tlsCipherSuite;

@end


/// 综合性能指标回调（等价于URLSessionTaskTransactionMetrics）
typedef void(^EMASCurlTransactionMetricsObserverBlock)(NSURLRequest * _Nonnull request,
                                                      BOOL success,
                                                      NSError * _Nullable error,
                                                      EMASCurlTransactionMetrics * _Nonnull metrics);


// HTTP版本，高版本一定包含支持低版本
typedef NS_ENUM(NSInteger, HTTPVersion) {
    HTTP1,
    HTTP2,
    HTTP3
};


/**
 * EMASCurl配置对象，封装所有网络设置
 * 每个NSURLSession可以拥有自己的配置实例
 */
@interface EMASCurlConfiguration : NSObject <NSCopying>

#pragma mark - 核心网络设置

/**
 * 请求使用的HTTP版本
 * 默认值: HTTP1
 */
@property (nonatomic, assign) HTTPVersion httpVersion;

/**
 * 连接超时时间（秒）
 * 默认值: 2.5秒
 */
@property (nonatomic, assign) NSTimeInterval connectTimeoutInterval;

/**
 * 是否启用内置gzip压缩
 * 默认值: YES
 */
@property (nonatomic, assign) BOOL enableBuiltInGzip;

/**
 * 是否启用内置重定向处理
 * 默认值: YES
 */
@property (nonatomic, assign) BOOL enableBuiltInRedirection;

#pragma mark - DNS和代理配置

/**
 * 自定义DNS解析器类
 * 默认值: nil (使用系统DNS)
 */
@property (nonatomic, strong, nullable) Class<EMASCurlProtocolDNSResolver> dnsResolver;

/**
 * 代理服务器URL
 * 格式: [protocol://]user:password@host[:port]
 * 示例: http://proxy.example.com:8080 或 socks5://127.0.0.1:1080
 * 默认值: nil
 */
@property (nonatomic, copy, nullable) NSString *proxyServer;

#pragma mark - 安全设置

/**
 * 自定义CA证书文件路径
 * 用于自签名证书
 * 默认值: nil
 */
@property (nonatomic, copy, nullable) NSString *caFilePath;

/**
 * 用于公钥固定的公钥文件路径
 * 默认值: nil
 */
@property (nonatomic, copy, nullable) NSString *publicKeyPinningKeyPath;

/**
 * 启用证书验证
 * 默认值: YES
 */
@property (nonatomic, assign) BOOL certificateValidationEnabled;

/**
 * 启用域名验证
 * 默认值: YES
 */
@property (nonatomic, assign) BOOL domainNameVerificationEnabled;

#pragma mark - 域名过滤

/**
 * 域名白名单 - 仅拦截对这些域名的请求
 * 默认值: nil (拦截所有)
 */
@property (nonatomic, copy, nullable) NSArray<NSString *> *domainWhiteList;

/**
 * 域名黑名单 - 不拦截对这些域名的请求
 * 默认值: nil (无黑名单)
 */
@property (nonatomic, copy, nullable) NSArray<NSString *> *domainBlackList;

#pragma mark - URL路径过滤

/**
 * URL路径黑名单 - 不拦截匹配这些路径的请求
 * 支持三种模式：
 * 1. 完全匹配: @"/sample/shouldnotintercept.do"
 * 2. 单级通配符: @"/sample/\*" - 匹配前缀及一个路径段（包含空段）
 * 3. 多级通配符: @"/sample/\*\*" - 匹配前缀及所有子路径
 * 默认值: nil (无路径黑名单)
 */
@property (nonatomic, copy, nullable) NSArray<NSString *> *urlPathBlackList;

#pragma mark - 缓存设置

/**
 * 启用HTTP响应缓存
 * 默认值: YES
 */
@property (nonatomic, assign) BOOL cacheEnabled;

/**
 * 可缓存响应体的最大内存大小（字节）。
 * 超过该阈值时将放弃在内存中累积响应体，从而避免内存暴涨引发崩溃；
 * 若需要缓存超大响应，请使用磁盘缓存方案。
 * 默认值：5 MiB。
 */
@property (nonatomic, assign) NSUInteger maximumCacheableBodyBytes;


#pragma mark - 性能监控

/**
 * 全局事务指标观察器
 * 对使用此配置的每个完成的请求调用
 * 默认值: nil
 */
@property (nonatomic, copy, nullable) EMASCurlTransactionMetricsObserverBlock transactionMetricsObserver;

#pragma mark - 工厂方法

/**
 * 创建具有标准设置的默认配置
 * @return 具有默认值的新配置
 */
+ (instancetype)defaultConfiguration;

#pragma mark - 配置管理

/**
 * 创建配置的深拷贝
 * @return 具有相同设置的新配置实例
 */
- (instancetype)copy;

/**
 * 与另一个配置进行比较
 * @param configuration 要比较的配置
 * @return 配置相同返回YES
 */
- (BOOL)isEqualToConfiguration:(EMASCurlConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
