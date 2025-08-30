//
//  EMASCurlConfiguration.m
//  EMASCurl
//
//  Created by EMASCurl on 2025/01/02.
//

#import "EMASCurlConfiguration.h"
#import "EMASCurlResponseCache.h"
#import "EMASCurlLogger.h"

@interface EMASCurlConfiguration () {
    dispatch_queue_t _propertyQueue;
}
@end

@implementation EMASCurlConfiguration

#pragma mark - 初始化

- (instancetype)init {
    self = [super init];
    if (self) {
        _propertyQueue = dispatch_queue_create("com.emas.curl.config", DISPATCH_QUEUE_CONCURRENT);
        [self setupDefaults];
    }
    return self;
}

- (void)setupDefaults {
    // 核心网络设置
    _httpVersion = HTTP1;
    _connectTimeoutInterval = 2.5;
    _enableBuiltInGzip = YES;
    _enableBuiltInRedirection = YES;

    // DNS和代理配置
    _dnsResolver = nil;
    _proxyServer = nil;
    _manualProxyEnabled = NO;

    // 安全设置
    _caFilePath = nil;
    _publicKeyPinningKeyPath = nil;
    _certificateValidationEnabled = YES;
    _domainNameVerificationEnabled = YES;

    // 域名过滤
    _domainWhiteList = nil;
    _domainBlackList = nil;

    // 缓存设置
    _cacheEnabled = YES; // Will be set to shared instance when needed

    // 性能监控
    _transactionMetricsObserver = nil;
}

#pragma mark - 工厂方法

+ (instancetype)defaultConfiguration {
    EMASCurlConfiguration *config = [[EMASCurlConfiguration alloc] init];
    return config;
}

+ (instancetype)apiConfiguration {
    EMASCurlConfiguration *config = [[EMASCurlConfiguration alloc] init];
    config.httpVersion = HTTP2;
    config.connectTimeoutInterval = 2.0;
    config.cacheEnabled = NO;
    config.enableBuiltInGzip = YES;
    config.enableBuiltInRedirection = NO; // API通常显式处理重定向
    return config;
}

+ (instancetype)downloadConfiguration {
    EMASCurlConfiguration *config = [[EMASCurlConfiguration alloc] init];
    config.httpVersion = HTTP2;
    config.connectTimeoutInterval = 10.0;
    config.cacheEnabled = YES;
    config.enableBuiltInGzip = YES;
    config.enableBuiltInRedirection = YES;
    return config;
}

#pragma mark - NSCopying协议

- (id)copyWithZone:(NSZone *)zone {
    EMASCurlConfiguration *copy = [[[self class] allocWithZone:zone] init];

    // 复制所有属性
    copy.httpVersion = self.httpVersion;
    copy.connectTimeoutInterval = self.connectTimeoutInterval;
    copy.enableBuiltInGzip = self.enableBuiltInGzip;
    copy.enableBuiltInRedirection = self.enableBuiltInRedirection;

    copy.dnsResolver = self.dnsResolver;
    copy.proxyServer = [self.proxyServer copy];
    copy.manualProxyEnabled = self.manualProxyEnabled;

    copy.caFilePath = [self.caFilePath copy];
    copy.publicKeyPinningKeyPath = [self.publicKeyPinningKeyPath copy];
    copy.certificateValidationEnabled = self.certificateValidationEnabled;
    copy.domainNameVerificationEnabled = self.domainNameVerificationEnabled;

    copy.domainWhiteList = [self.domainWhiteList copy];
    copy.domainBlackList = [self.domainBlackList copy];

    copy.cacheEnabled = self.cacheEnabled;
    // 缓存全局管理，不属于配置

    copy.transactionMetricsObserver = [self.transactionMetricsObserver copy];

    return copy;
}

- (instancetype)copy {
    return [self copyWithZone:nil];
}

#pragma mark - 验证

- (BOOL)validateWithError:(NSError **)error {
    // 验证超时设置
    if (self.connectTimeoutInterval <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"EMASCurlConfiguration"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Connect timeout must be positive"}];
        }
        return NO;
    }

    // 如果启用手动代理，验证代理URL格式
    if (self.manualProxyEnabled && self.proxyServer) {
        NSURL *proxyURL = [NSURL URLWithString:self.proxyServer];
        if (!proxyURL || !proxyURL.host) {
            if (error) {
                *error = [NSError errorWithDomain:@"EMASCurlConfiguration"
                                             code:1002
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid proxy server URL format"}];
            }
            return NO;
        }
    }

    // 验证指定的文件路径是否存在
    if (self.caFilePath) {
        BOOL isDirectory;
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.caFilePath isDirectory:&isDirectory] || isDirectory) {
            if (error) {
                *error = [NSError errorWithDomain:@"EMASCurlConfiguration"
                                             code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: @"CA file path does not exist or is a directory"}];
            }
            return NO;
        }
    }

    if (self.publicKeyPinningKeyPath) {
        BOOL isDirectory;
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.publicKeyPinningKeyPath isDirectory:&isDirectory] || isDirectory) {
            if (error) {
                *error = [NSError errorWithDomain:@"EMASCurlConfiguration"
                                             code:1004
                                         userInfo:@{NSLocalizedDescriptionKey: @"Public key file path does not exist or is a directory"}];
            }
            return NO;
        }
    }

    return YES;
}

#pragma mark - 比较

- (BOOL)isEqualToConfiguration:(EMASCurlConfiguration *)configuration {
    if (!configuration) return NO;
    if (self == configuration) return YES;

    // 比较所有属性
    if (self.httpVersion != configuration.httpVersion) return NO;
    if (self.connectTimeoutInterval != configuration.connectTimeoutInterval) return NO;
    if (self.enableBuiltInGzip != configuration.enableBuiltInGzip) return NO;
    if (self.enableBuiltInRedirection != configuration.enableBuiltInRedirection) return NO;

    if (self.dnsResolver != configuration.dnsResolver) return NO;
    if ((self.proxyServer || configuration.proxyServer) &&
        ![self.proxyServer isEqualToString:configuration.proxyServer]) return NO;
    if (self.manualProxyEnabled != configuration.manualProxyEnabled) return NO;

    if ((self.caFilePath || configuration.caFilePath) &&
        ![self.caFilePath isEqualToString:configuration.caFilePath]) return NO;
    if ((self.publicKeyPinningKeyPath || configuration.publicKeyPinningKeyPath) &&
        ![self.publicKeyPinningKeyPath isEqualToString:configuration.publicKeyPinningKeyPath]) return NO;
    if (self.certificateValidationEnabled != configuration.certificateValidationEnabled) return NO;
    if (self.domainNameVerificationEnabled != configuration.domainNameVerificationEnabled) return NO;

    if ((self.domainWhiteList || configuration.domainWhiteList) &&
        ![self.domainWhiteList isEqualToArray:configuration.domainWhiteList]) return NO;
    if ((self.domainBlackList || configuration.domainBlackList) &&
        ![self.domainBlackList isEqualToArray:configuration.domainBlackList]) return NO;

    if (self.cacheEnabled != configuration.cacheEnabled) return NO;

    // 注意：不比较block (transactionMetricsObserver)

    return YES;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[EMASCurlConfiguration class]]) {
        return NO;
    }
    return [self isEqualToConfiguration:object];
}

- (NSUInteger)hash {
    NSUInteger hash = 0;
    hash ^= self.httpVersion;
    hash ^= [@(self.connectTimeoutInterval) hash];
    hash ^= self.enableBuiltInGzip ? 1 : 0;
    hash ^= self.enableBuiltInRedirection ? 2 : 0;
    hash ^= [self.proxyServer hash];
    hash ^= self.manualProxyEnabled ? 4 : 0;
    hash ^= [self.caFilePath hash];
    hash ^= [self.publicKeyPinningKeyPath hash];
    hash ^= self.certificateValidationEnabled ? 8 : 0;
    hash ^= self.domainNameVerificationEnabled ? 16 : 0;
    hash ^= [self.domainWhiteList hash];
    hash ^= [self.domainBlackList hash];
    hash ^= self.cacheEnabled ? 32 : 0;
    return hash;
}

#pragma mark - 描述

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, httpVersion=%ld, connectTimeout=%.1f, gzip=%@, redirect=%@, proxy=%@>",
            NSStringFromClass([self class]),
            self,
            (long)self.httpVersion,
            self.connectTimeoutInterval,
            self.enableBuiltInGzip ? @"YES" : @"NO",
            self.enableBuiltInRedirection ? @"YES" : @"NO",
            self.proxyServer ?: @"none"];
}

@end
