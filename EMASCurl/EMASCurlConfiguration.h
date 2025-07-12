//
//  EMASCurlConfiguration.h
//  EMASCurl
//
//  Created by assistant on 2025/07/12.
//

#ifndef EMASCurlConfiguration_h
#define EMASCurlConfiguration_h

#import <Foundation/Foundation.h>

// Forward declarations
@protocol EMASCurlProtocolDNSResolver;

// HTTP版本，高版本一定包含支持低版本
typedef NS_ENUM(NSInteger, HTTPVersion) {
    HTTP1,
    HTTP2,
    HTTP3
};

// 日志级别枚举
typedef NS_ENUM(NSInteger, EMASCurlLogLevel) {
    EMASCurlLogLevelOff = 0,      // 禁用所有日志
    EMASCurlLogLevelError = 1,    // 仅错误信息
    EMASCurlLogLevelInfo = 2,     // 信息和错误
    EMASCurlLogLevelDebug = 3,    // 调试信息和以上所有，包括libcurl输出
};

@interface EMASCurlConfiguration : NSObject <NSCopying>

#pragma mark - HTTP Configuration

/// HTTP版本设置，默认HTTP2
@property (nonatomic, assign) HTTPVersion httpVersion;

/// 是否开启内部Gzip压缩，默认YES
@property (nonatomic, assign) BOOL builtInGzipEnabled;

/// 是否开启内部重定向支持，默认YES
@property (nonatomic, assign) BOOL builtInRedirectionEnabled;

#pragma mark - SSL/TLS Configuration

/// CA证书文件路径，用于自签名证书
@property (nonatomic, copy, nullable) NSString *selfSignedCAFilePath;

/// 是否开启证书校验，默认YES
@property (nonatomic, assign) BOOL certificateValidationEnabled;

/// 是否开启域名校验，默认YES
@property (nonatomic, assign) BOOL domainNameVerificationEnabled;

/// 公钥固定(Public Key Pinning)的公钥文件路径
@property (nonatomic, copy, nullable) NSString *publicKeyPinningKeyPath;

#pragma mark - DNS Configuration

/// DNS解析器类
@property (nonatomic, assign, nullable) Class<EMASCurlProtocolDNSResolver> dnsResolverClass;

#pragma mark - Proxy Configuration

/// 手动代理服务器URL
@property (nonatomic, copy, nullable) NSString *manualProxyServer;

#pragma mark - Domain Filtering Configuration

/// 拦截域名白名单
@property (nonatomic, copy, nullable) NSArray<NSString *> *hijackDomainWhiteList;

/// 拦截域名黑名单
@property (nonatomic, copy, nullable) NSArray<NSString *> *hijackDomainBlackList;

#pragma mark - Cache Configuration

/// 是否启用HTTP缓存，默认NO
@property (nonatomic, assign) BOOL cacheEnabled;

#pragma mark - Initialization

/// 创建默认配置
+ (nonnull instancetype)defaultConfiguration;

#pragma mark - Convenience Methods

/// 设置DNS解析器
- (void)setDNSResolver:(nonnull Class<EMASCurlProtocolDNSResolver>)dnsResolver;

@end

#endif /* EMASCurlConfiguration_h */
