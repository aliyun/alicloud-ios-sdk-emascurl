//
//  EMASCurlProtocol.m
//  EMASCurl
//
//  Created by xin yu on 2024/10/29.
//

#import "EMASCurlProtocol.h"
#import "EMASCurlManager.h"
#import "EMASCurlCookieStorage.h"
#import "EMASCurlResponseCache.h"
#import "NSCachedURLResponse+EMASCurl.h"
#import "EMASCurlLogger.h"
#import "EMASCurlConfiguration.h"
#import "EMASCurlConfigurationManager.h"
#import "EMASCurlProxySetting.h"
#import <curl/curl.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <NetworkExtension/NetworkExtension.h>

#define HTTP_METHOD_GET @"GET"
#define HTTP_METHOD_PUT @"PUT"
#define HTTP_METHOD_POST @"POST"
#define HTTP_METHOD_HEAD @"HEAD"
#define HTTP_METHOD_DELETE @"DELETE"
#define HTTP_METHOD_PATCH @"PATCH"
#define HTTP_METHOD_OPTIONS @"OPTIONS"
#define HTTP_METHOD_TRACE @"TRACE"
#define HTTP_METHOD_CONNECT @"CONNECT"

static NSString * _Nonnull const kEMASCurlUploadProgressUpdateBlockKey = @"kEMASCurlUploadProgressUpdateBlockKey";
static NSString * _Nonnull const kEMASCurlMetricsObserverBlockKey = @"kEMASCurlMetricsObserverBlockKey";

static NSString * _Nonnull const kEMASCurlConnectTimeoutIntervalKey = @"kEMASCurlConnectTimeoutIntervalKey";
static NSString * _Nonnull const kEMASCurlHandledKey = @"kEMASCurlHandledKey";

// Multi-instance configuration support
static NSString * _Nonnull const kEMASCurlConfigurationIDKey = @"kEMASCurlConfigurationIDKey";
static NSString * _Nonnull const kEMASCurlConfigurationHeaderKey = @"X-EMASCurl-Config-ID";

// RFC 7234 可能可缓存的状态码（实际可缓存性由 emas_cachedResponseWithHTTPURLResponse 决定）
static BOOL isPotentiallyCacheableStatusCode(NSInteger statusCode) {
    switch (statusCode) {
        case 200: // OK
        case 203: // Non-Authoritative Information
        case 204: // No Content
        case 206: // Partial Content
        case 300: // Multiple Choices
        case 301: // Moved Permanently
        case 404: // Not Found
        case 405: // Method Not Allowed
        case 410: // Gone
        case 414: // URI Too Long
        case 501: // Not Implemented
            return YES;
        default:
            return NO;
    }
}

/**
 * 检查请求路径是否匹配黑名单模式
 * @param requestPath 请求的URL路径
 * @param pattern 黑名单模式
 * @return 匹配返回YES
 */
static BOOL emas_pathMatchesPattern(NSString *requestPath, NSString *pattern) {
    if (!requestPath || !pattern) {
        return NO;
    }

    // 多级通配符: "/sample/**"
    if ([pattern hasSuffix:@"/**"]) {
        NSString *prefix = [pattern substringToIndex:pattern.length - 3];
        // 匹配前缀本身或前缀加任意后续路径
        return [requestPath isEqualToString:prefix] ||
               [requestPath hasPrefix:[prefix stringByAppendingString:@"/"]];
    }

    // 单级通配符: "/sample/*"
    if ([pattern hasSuffix:@"/*"]) {
        NSString *prefix = [pattern substringToIndex:pattern.length - 2];
        // 匹配前缀本身（无尾斜杠）
        if ([requestPath isEqualToString:prefix]) {
            return YES;
        }
        // 匹配 prefix/ 开头，且之后不能再有 /
        if ([requestPath hasPrefix:[prefix stringByAppendingString:@"/"]]) {
            NSString *remaining = [requestPath substringFromIndex:prefix.length + 1];
            return ![remaining containsString:@"/"];
        }
        return NO;
    }

    // 完全匹配
    return [requestPath isEqualToString:pattern];
}

// EMASCurlTransactionMetrics实现
@implementation EMASCurlTransactionMetrics
@end

@interface CurlHTTPResponse : NSObject

@property (nonatomic, assign) NSInteger statusCode;

@property (nonatomic, strong) NSString *httpVersion;

@property (nonatomic, strong) NSString *reasonPhrase;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *headers;

@property (nonatomic, assign) BOOL isFinalResponse;

@end

@implementation CurlHTTPResponse

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reset];
    }
    return self;
}

- (void)reset {
    _statusCode = 0;
    _httpVersion = nil;
    _reasonPhrase = nil;
    _headers = [NSMutableDictionary new];
    _isFinalResponse = NO;
}

@end

@interface EMASCurlProtocol()

@property (nonatomic, assign) CURL *easyHandle;

@property (nonatomic, strong) NSInputStream *inputStream;

@property (nonatomic, assign) struct curl_slist *requestHeaderFields;

@property (nonatomic, assign) struct curl_slist *resolveList;

@property (nonatomic, assign) int64_t totalBytesSent;

@property (nonatomic, assign) int64_t totalBytesExpected;

@property (nonatomic, strong) CurlHTTPResponse *currentResponse;

@property (atomic, assign) BOOL shouldCancel;

@property (atomic, strong) dispatch_semaphore_t cleanupSemaphore;

@property (nonatomic, copy) EMASCurlUploadProgressUpdateBlock uploadProgressUpdateBlock;

@property (nonatomic, copy) EMASCurlMetricsObserverBlock metricsObserverBlock;

@property (nonatomic, assign) double resolveDomainTimeInterval;

@property (nonatomic, assign) BOOL usedCustomDNSResolverResult;

@property (nonatomic, strong) NSMutableData *receivedResponseData;

@property (nonatomic, strong) EMASCurlConfiguration *resolvedConfiguration;

// 缓存缓冲控制
@property (nonatomic, assign) BOOL shouldBufferBodyForCache;
@property (nonatomic, assign) NSUInteger bufferedCacheBytes;

// 时间记录属性
@property (nonatomic, strong) NSDate *fetchStartDate;
@property (nonatomic, strong) NSDate *domainLookupStartDate;
@property (nonatomic, strong) NSDate *domainLookupEndDate;
@property (nonatomic, strong) NSDate *connectStartDate;
@property (nonatomic, strong) NSDate *secureConnectionStartDate;
@property (nonatomic, strong) NSDate *secureConnectionEndDate;
@property (nonatomic, strong) NSDate *connectEndDate;
@property (nonatomic, strong) NSDate *requestStartDate;
@property (nonatomic, strong) NSDate *requestEndDate;
@property (nonatomic, strong) NSDate *responseStartDate;
@property (nonatomic, strong) NSDate *responseEndDate;

// 客户端回调线程/RunLoop信息
@property (nonatomic, strong) NSThread *clientThread;
@property (nonatomic, strong) NSArray<NSString *> *clientRunLoopModes;

// 生命周期与幂等控制
@property (atomic, assign) BOOL clientNotified;   // 保证只通知一次客户端
@property (atomic, assign) BOOL cancelled;        // 是否已触发取消
@property (atomic, assign) BOOL cleanedUp;        // 资源是否已清理

@end

@interface EMASCurlProtocol (ClientThreading)

- (void)invokeOnClientThread:(dispatch_block_t)block;

- (BOOL)markClientNotifiedIfNeeded;

- (BOOL)hasClientNotified;

- (void)cleanupIfNeeded;

@end

// runtime 的libcurl xcframework是否支持HTTP2
static BOOL curlFeatureHttp2;

// runtime 的libcurl xcframework是否支持HTTP3
static BOOL curlFeatureHttp3;

// 全局日志设置
static BOOL s_enableDebugLog;

// 全局请求拦截开关
static BOOL s_requestInterceptEnabled = YES;

// 全局缓存相关
static EMASCurlResponseCache *s_responseCache;

// 全局综合性能指标观察回调
static EMASCurlTransactionMetricsObserverBlock globalTransactionMetricsObserverBlock = nil;

@implementation EMASCurlProtocol

#pragma mark * user API

+ (void)installIntoSessionConfiguration:(nonnull NSURLSessionConfiguration*)sessionConfiguration {
    NSMutableArray *protocolsArray = [NSMutableArray arrayWithArray:sessionConfiguration.protocolClasses];
    [protocolsArray insertObject:self atIndex:0];
    [sessionConfiguration setProtocolClasses:protocolsArray];
}

+ (void)registerCurlProtocol {
    [NSURLProtocol registerClass:self];
}

+ (void)unregisterCurlProtocol {
    [NSURLProtocol unregisterClass:self];
}

+ (void)setHTTPVersion:(HTTPVersion)version {
    // 更新默认配置
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.httpVersion = version;
}

+ (void)setBuiltInGzipEnabled:(BOOL)enabled {
    // 更新默认配置
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.enableBuiltInGzip = enabled;
}

+ (void)setSelfSignedCAFilePath:(nonnull NSString *)selfSignedCAFilePath {
    // 更新默认配置
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.caFilePath = selfSignedCAFilePath;
}

+ (void)setBuiltInRedirectionEnabled:(BOOL)enabled {
    // 更新默认配置
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.enableBuiltInRedirection = enabled;
}

+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled {
    s_enableDebugLog = debugLogEnabled;
    // 向后兼容性：映射到新的日志级别系统
    if (debugLogEnabled) {
        [EMASCurlLogger setLogLevel:EMASCurlLogLevelDebug];
    } else {
        [EMASCurlLogger setLogLevel:EMASCurlLogLevelOff];
    }
}

+ (void)setDNSResolver:(nonnull Class<EMASCurlProtocolDNSResolver>)dnsResolver {
    // 更新默认配置
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.dnsResolver = dnsResolver;
}

+ (void)setUploadProgressUpdateBlockForRequest:(nonnull NSMutableURLRequest *)request uploadProgressUpdateBlock:(nonnull EMASCurlUploadProgressUpdateBlock)uploadProgressUpdateBlock {
    [NSURLProtocol setProperty:[uploadProgressUpdateBlock copy] forKey:kEMASCurlUploadProgressUpdateBlockKey inRequest:request];
}

+ (void)setGlobalTransactionMetricsObserverBlock:(nullable EMASCurlTransactionMetricsObserverBlock)transactionMetricsObserverBlock {
    @synchronized (self) {
        globalTransactionMetricsObserverBlock = [transactionMetricsObserverBlock copy];
    }
}

+ (void)setMetricsObserverBlockForRequest:(nonnull NSMutableURLRequest *)request metricsObserverBlock:(nonnull EMASCurlMetricsObserverBlock)metricsObserverBlock {
    [NSURLProtocol setProperty:[metricsObserverBlock copy] forKey:kEMASCurlMetricsObserverBlockKey inRequest:request];
}

+ (void)setConnectTimeoutIntervalForRequest:(nonnull NSMutableURLRequest *)request connectTimeoutInterval:(NSTimeInterval)timeoutInterval {
    [NSURLProtocol setProperty:@(timeoutInterval) forKey:kEMASCurlConnectTimeoutIntervalKey inRequest:request];
}

+ (void)setConnectTimeoutInterval:(NSTimeInterval)timeoutInterval {
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.connectTimeoutInterval = timeoutInterval;
    EMAS_LOG_INFO(@"EC-Config", @"Connect timeout set to %.1f seconds", timeoutInterval);
}

+ (void)setHijackDomainWhiteList:(nullable NSArray<NSString *> *)domainWhiteList {
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.domainWhiteList = domainWhiteList;
}

+ (void)setHijackDomainBlackList:(nullable NSArray<NSString *> *)domainBlackList {
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.domainBlackList = domainBlackList;
}

+ (void)setHijackUrlPathBlackList:(nullable NSArray<NSString *> *)urlPathBlackList {
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.urlPathBlackList = urlPathBlackList;
}

+ (void)setPublicKeyPinningKeyPath:(nullable NSString *)publicKeyPath {
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.publicKeyPinningKeyPath = publicKeyPath;
}

+ (void)setCertificateValidationEnabled:(BOOL)enabled {
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.certificateValidationEnabled = enabled;
}

+ (void)setDomainNameVerificationEnabled:(BOOL)enabled {
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.domainNameVerificationEnabled = enabled;
}

+ (void)setManualProxyServer:(nullable NSString *)proxyServerURL {
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.proxyServer = proxyServerURL;
    [EMASCurlProxySetting setManualProxyServer:proxyServerURL];
}

+ (void)setCacheEnabled:(BOOL)enabled {
    // 更新默认配置
    EMASCurlConfiguration *defaultConfig = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    defaultConfig.cacheEnabled = enabled;
}

+ (void)setMaxConcurrentStreams:(NSInteger)maxStreams {
    [[EMASCurlManager sharedInstance] setMaxConcurrentStreams:maxStreams];
}

+ (void)setRequestInterceptEnabled:(BOOL)requestInterceptEnabled {
    @synchronized (self) {
        s_requestInterceptEnabled = requestInterceptEnabled;
    }
    if (requestInterceptEnabled) {
        EMAS_LOG_INFO(@"EC-Protocol", @"Request intercept enabled");
    } else {
        EMAS_LOG_INFO(@"EC-Protocol", @"Request intercept disabled");
    }
}

+ (BOOL)isRequestInterceptEnabled {
    @synchronized (self) {
        return s_requestInterceptEnabled;
    }
}

#pragma mark * NSURLProtocol overrides

// 使用 +initialize 承担一次性初始化；运行时保证对每个类只调用一次
+ (void)initialize {
    if (self != [EMASCurlProtocol class]) {
        return;
    }

    curl_global_init(CURL_GLOBAL_DEFAULT);

    // 读取 runtime 中 libcurl 对 HTTP/2 与 HTTP/3 的能力位，供后续配置分支使用
    curl_version_info_data *version_info = curl_version_info(CURLVERSION_NOW);
    curlFeatureHttp2 = (version_info->features & CURL_VERSION_HTTP2) ? YES : NO;
    curlFeatureHttp3 = (version_info->features & CURL_VERSION_HTTP3) ? YES : NO;

    s_enableDebugLog = NO;

    s_responseCache = [EMASCurlResponseCache new];

    // 显式引用以触发 EMASCurlProxySetting 的 +initialize，确保尽早建立系统代理监听
    (void)[EMASCurlProxySetting class];
}

- (instancetype)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id<NSURLProtocolClient>)client {
    self = [super initWithRequest:request cachedResponse:cachedResponse client:client];
    if (self) {
        _shouldCancel = NO;
        _cleanupSemaphore = dispatch_semaphore_create(0);
        _totalBytesSent = 0;
        _totalBytesExpected = 0;
        _currentResponse = [CurlHTTPResponse new];
        _resolveDomainTimeInterval = -1;
        _usedCustomDNSResolverResult = NO;

        // 初始化时间记录
        _fetchStartDate = [NSDate date];
        _receivedResponseData = [NSMutableData new];
        _shouldBufferBodyForCache = NO;
        _bufferedCacheBytes = 0;

        _uploadProgressUpdateBlock = [NSURLProtocol propertyForKey:kEMASCurlUploadProgressUpdateBlockKey inRequest:request];
        _metricsObserverBlock = [NSURLProtocol propertyForKey:kEMASCurlMetricsObserverBlockKey inRequest:request];

        _clientNotified = NO;
        _cancelled = NO;
        _cleanedUp = NO;
    }
    return self;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 全局拦截开关检查
    if (![self isRequestInterceptEnabled]) {
        return NO;
    }

    if ([[request.URL absoluteString] isEqual:@"about:blank"]) {
        EMAS_LOG_DEBUG(@"EC-Request", @"Rejected blank URL request");
        return NO;
    }

    // 不拦截已经处理过的请求
    if ([NSURLProtocol propertyForKey:kEMASCurlHandledKey inRequest:request]) {
        return NO;
    }

    // 不是http或https，则不拦截
    if (!([request.URL.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
         [request.URL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)) {
        EMAS_LOG_DEBUG(@"EC-Request", @"Rejected non-HTTP(S) request: %@", request.URL.scheme);
        return NO;
    }

    // 检查请求的host是否在白名单或黑名单中
    NSString *host = request.URL.host;
    if (!host) {
        EMAS_LOG_DEBUG(@"EC-Request", @"Rejected request without host");
        return NO;
    }

    // 尝试获取请求特定的配置
    EMASCurlConfiguration *config = nil;
    NSString *configID = [request valueForHTTPHeaderField:kEMASCurlConfigurationHeaderKey];
    if (configID) {
        config = [[EMASCurlConfigurationManager sharedManager] configurationForID:configID];
    }
    if (!config) {
        // 使用默认配置
        config = [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
    }

    // 使用配置中的域名黑白名单
    NSArray<NSString *> *domainBlackList = config.domainBlackList;
    NSArray<NSString *> *domainWhiteList = config.domainWhiteList;

    // 域名黑名单检查
    if (domainBlackList && domainBlackList.count > 0) {
        for (NSString *blacklistDomain in domainBlackList) {
            if ([host hasSuffix:blacklistDomain]) {
                EMAS_LOG_DEBUG(@"EC-Request", @"Request rejected by domain blacklist: %@", host);
                return NO;
            }
        }
    }

    // 域名白名单检查（重构：记录结果而非直接返回，以便后续路径检查能执行）
    if (domainWhiteList && domainWhiteList.count > 0) {
        BOOL passedDomainWhitelist = NO;
        for (NSString *whitelistDomain in domainWhiteList) {
            if ([host hasSuffix:whitelistDomain]) {
                passedDomainWhitelist = YES;
                EMAS_LOG_DEBUG(@"EC-Request", @"Request matched domain whitelist: %@", host);
                break;
            }
        }
        if (!passedDomainWhitelist) {
            EMAS_LOG_DEBUG(@"EC-Request", @"Request rejected: not in domain whitelist: %@", host);
            return NO;
        }
    }

    // URL路径黑名单检查
    NSString *urlPath = request.URL.path;
    NSArray<NSString *> *pathBlackList = config.urlPathBlackList;
    if (pathBlackList && pathBlackList.count > 0 && urlPath.length > 0) {
        for (NSString *pathPattern in pathBlackList) {
            if (emas_pathMatchesPattern(urlPath, pathPattern)) {
                EMAS_LOG_DEBUG(@"EC-Request", @"Request rejected by path blacklist: %@ (pattern: %@)", urlPath, pathPattern);
                return NO;
            }
        }
    }

    NSString *userAgent = [request valueForHTTPHeaderField:@"User-Agent"];
    if (userAgent && [userAgent containsString:@"HttpdnsSDK"]) {
        // 不拦截来自Httpdns SDK的请求
        EMAS_LOG_DEBUG(@"EC-Request", @"Rejected HttpdnsSDK request");
        return NO;
    }

    // 检查是否在系统代理时禁用EMASCurl（手动配置代理时不生效）
    if (config.disabledWhenUsingSystemProxy && config.proxyServer.length == 0) {
        NSString *systemProxy = [EMASCurlProxySetting proxyServerForURL:request.URL];
        if (systemProxy.length > 0) {
            EMAS_LOG_INFO(@"EC-Request", @"Skipping EMASCurl due to system proxy detected: %@", systemProxy);
            return NO;
        }
    }

    EMAS_LOG_DEBUG(@"EC-Request", @"Request accepted for processing: %@", request.URL.absoluteString);
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kEMASCurlHandledKey inRequest:mutableRequest];

    // 从HTTP header中提取配置ID并设置为protocol property
    NSString *configID = [request valueForHTTPHeaderField:kEMASCurlConfigurationHeaderKey];
    if (configID) {
        [NSURLProtocol setProperty:configID forKey:kEMASCurlConfigurationIDKey inRequest:mutableRequest];
    }

    return mutableRequest;
}

- (EMASCurlConfiguration *)resolveConfiguration {
    // 尝试从protocol property中获取配置ID
    NSString *configID = [NSURLProtocol propertyForKey:kEMASCurlConfigurationIDKey inRequest:self.request];

    if (configID) {
        EMASCurlConfiguration *config = [[EMASCurlConfigurationManager sharedManager] configurationForID:configID];
        if (config) {
            EMAS_LOG_DEBUG(@"EC-MultiInstance", @"Using configuration %@ for request", configID);
            return config;
        }
    }

    // 如果没有找到特定配置，使用默认配置
    EMAS_LOG_DEBUG(@"EC-MultiInstance", @"Using default configuration for request");
    return [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
}

- (void)startLoading {
    EMAS_LOG_INFO(@"EC-Protocol", @"Starting request for URL: %@", self.request.URL.absoluteString);

    // 记录客户端调度线程与常用RunLoop模式
    self.clientThread = [NSThread currentThread];
    self.clientRunLoopModes = @[NSDefaultRunLoopMode, NSRunLoopCommonModes];

    // 解析此请求应使用的配置
    self.resolvedConfiguration = [self resolveConfiguration];

    // 检查是否启用缓存以及是否是可缓存的请求
    BOOL useCache = NO;
    NSCachedURLResponse *hitCachedResponse = nil;

    if (self.resolvedConfiguration.cacheEnabled &&
        [[self.request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {

        // 从我们的缓存逻辑获取响应
        NSCachedURLResponse *cachedResponse = [s_responseCache cachedResponseForRequest:self.request];

        if (cachedResponse) {
            BOOL isFresh = [cachedResponse emas_isResponseStillFreshForRequest:self.request];
            BOOL requiresRevalidation = [cachedResponse emas_requiresRevalidation];

            if (isFresh && !requiresRevalidation) {
                // 响应是新鲜的，且不需要因为 no-cache 等指令而重新验证
                useCache = YES; // 标记已使用缓存
                hitCachedResponse = cachedResponse;
                EMAS_LOG_INFO(@"EC-Cache", @"Cache hit for request: %@", self.request.URL.absoluteString);
            } else {
                // 响应是陈旧的，或者新鲜但需要重新验证 (no-cache)。
                // 条件请求头将在后续步骤中添加 (如果 cachedResponse 有 ETag/Last-Modified)。
                // cachedResponseForRequest 保证了如果到这里 cachedResponse 非nil，它至少有验证器。
                EMAS_LOG_DEBUG(@"EC-Cache", @"Cache validation: fresh=%d, requires_revalidation=%d", isFresh, requiresRevalidation);
            }
        }
    }

    // 如果使用了缓存，则直接返回
    if (useCache) {
        [self reportCacheHitMetrics];
        [self invokeOnClientThread:^{
            if (![self markClientNotifiedIfNeeded]) {
                return;
            }
            [self.client URLProtocol:self didReceiveResponse:hitCachedResponse.response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:hitCachedResponse.data];
            [self.client URLProtocolDidFinishLoading:self];
            [self cleanupIfNeeded];
        }];
        return;
    }

    // 原始的网络请求处理逻辑
    CURL *easyHandle = curl_easy_init();
    self.easyHandle = easyHandle;
    if (!easyHandle) {
        NSError *error = [NSError errorWithDomain:@"fail to init easy handle." code:-1 userInfo:nil];
        EMAS_LOG_ERROR(@"EC-Protocol", @"Failed to create easy handle for URL: %@", self.request.URL.absoluteString);
        [self reportEarlyFailure:error];
        [self invokeOnClientThread:^{
            if (![self markClientNotifiedIfNeeded]) {
                return;
            }
            [self.client URLProtocol:self didFailWithError:error];
            [self cleanupIfNeeded];
        }];
        return;
    }

    EMAS_LOG_DEBUG(@"EC-Protocol", @"Easy handle created successfully for URL: %@", self.request.URL.absoluteString);

    [self populateRequestHeader:easyHandle];
    [self populateRequestBody:easyHandle];

    NSError *error = nil;
    [self configEasyHandle:easyHandle error:&error];
    if (error) {
        EMAS_LOG_ERROR(@"EC-Protocol", @"Failed to configure easy handle: %@", error.localizedDescription);
        [self reportEarlyFailure:error];
        // handle 未添加到 multi，需手动 cleanup 避免泄漏
        curl_easy_cleanup(easyHandle);
        self.easyHandle = nil;
        [self invokeOnClientThread:^{
            if (![self markClientNotifiedIfNeeded]) {
                return;
            }
            [self.client URLProtocol:self didFailWithError:error];
            [self cleanupIfNeeded];
        }];
        return;
    }

    [[EMASCurlManager sharedInstance] enqueueNewEasyHandle:easyHandle completion:^(BOOL succeed, NSError *error, EMASCurlMetricsData *metrics) {
        [self reportNetworkMetricWithData:metrics success:succeed error:error];

        // 从 metrics 获取重定向信息（在 Manager 中 curl_easy_cleanup 之前已提取）
        long redirectCount = metrics.redirectCount;

        // 如果发生重定向，获取最终URL
        NSURL *effectiveURL = self.request.URL;
        if (redirectCount > 0 && metrics.effectiveURL) {
            NSURL *parsedURL = [NSURL URLWithString:metrics.effectiveURL];
            if (parsedURL) {
                effectiveURL = parsedURL;
            }
        }

        // 如果请求成功且状态码可缓存，则尝试缓存响应（仅在内存中曾经缓冲成功时）
        if (succeed &&
            isPotentiallyCacheableStatusCode(self.currentResponse.statusCode) &&
            self.resolvedConfiguration.cacheEnabled &&
            [[self.request.HTTPMethod uppercaseString] isEqualToString:@"GET"] &&
            self.receivedResponseData != nil) {

            NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:effectiveURL
                                                                          statusCode:self.currentResponse.statusCode
                                                                         HTTPVersion:self.currentResponse.httpVersion
                                                                        headerFields:self.currentResponse.headers];
            if (httpResponse) {
                NSURLRequest *cacheKeyRequest = self.request;
                if (redirectCount > 0) {
                    // 重定向场景：使用最终URL作为缓存键
                    NSMutableURLRequest *redirectedRequest = [self.request mutableCopy];
                    [redirectedRequest setURL:effectiveURL];
                    cacheKeyRequest = redirectedRequest;
                    EMAS_LOG_INFO(@"EC-Cache", @"Response cached for redirected URL: %@ (original: %@)",
                                  effectiveURL.absoluteString, self.request.URL.absoluteString);
                } else {
                    EMAS_LOG_INFO(@"EC-Cache", @"Response cached for URL: %@", self.request.URL.absoluteString);
                }
                [s_responseCache cacheResponse:httpResponse
                                          data:self.receivedResponseData
                                    forRequest:cacheKeyRequest
                               withHTTPVersion:self.currentResponse.httpVersion];
            }
        }

        [self invokeOnClientThread:^{
            // 仅在尚未通知客户端时发送回调，但无论如何都要执行资源清理
            if ([self markClientNotifiedIfNeeded]) {
                if (self.cancelled) {
                    NSError *cancelErr = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
                    EMAS_LOG_INFO(@"EC-Protocol", @"Request cancelled, notifying client");
                    [self.client URLProtocol:self didFailWithError:cancelErr];
                } else if (succeed) {
                    EMAS_LOG_DEBUG(@"EC-Protocol", @"Request processing completed with status: %ld", (long)self.currentResponse.statusCode);
                    [self.client URLProtocolDidFinishLoading:self];
                } else {
                    EMAS_LOG_ERROR(@"EC-Protocol", @"Request failed: %@", error ? error.localizedDescription : @"Unknown error");
                    [self.client URLProtocol:self didFailWithError:error];
                }
            }
            // 无论是否通知客户端，都必须清理资源（curl 此时已完成处理）
            [self cleanupIfNeeded];
        }];
    }];
}

- (void)stopLoading {
    self.shouldCancel = YES;
    self.cancelled = YES;
    // 提醒网络线程尽快从 curl_multi_wait 唤醒，进入 progress 回调并中止
    [[EMASCurlManager sharedInstance] wakeup];

    // 非阻塞：立即返回。客户端取消通知切回调度线程且保证只发一次
    // 注意：这里不调用 cleanupIfNeeded，因为 curl 可能仍在访问 requestHeaderFields/resolveList，
    // 资源清理统一由 Manager 的 completion 回调触发，确保 curl 已完成处理
    [self invokeOnClientThread:^{
        if (![self markClientNotifiedIfNeeded]) {
            return;
        }
        NSError *cancelErr = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
        [self.client URLProtocol:self didFailWithError:cancelErr];
    }];
}

// 早期错误时通知 observer，metrics 全为 0（无网络活动）
- (void)reportEarlyFailure:(NSError *)error {
    EMASCurlTransactionMetricsObserverBlock globalCallback = nil;
    @synchronized ([EMASCurlProtocol class]) {
        globalCallback = globalTransactionMetricsObserverBlock;
    }
    EMASCurlTransactionMetricsObserverBlock instanceCallback = self.resolvedConfiguration.transactionMetricsObserver;

    // 创建空的 metrics 对象，fetchStartDate 复用请求开始时间
    EMASCurlTransactionMetrics *emptyMetrics = [[EMASCurlTransactionMetrics alloc] init];
    emptyMetrics.fetchStartDate = self.fetchStartDate ?: [NSDate date];

    if (globalCallback) {
        globalCallback(self.request, NO, error, emptyMetrics);
    }
    if (instanceCallback) {
        instanceCallback(self.request, NO, error, emptyMetrics);
    }
    if (self.metricsObserverBlock) {
        self.metricsObserverBlock(self.request, NO, error, 0, 0, 0, 0, 0, 0);
    }
}

// 缓存命中时通知 observer，所有网络时间为 0
- (void)reportCacheHitMetrics {
    EMASCurlTransactionMetricsObserverBlock globalCallback = nil;
    @synchronized ([EMASCurlProtocol class]) {
        globalCallback = globalTransactionMetricsObserverBlock;
    }
    EMASCurlTransactionMetricsObserverBlock instanceCallback = self.resolvedConfiguration.transactionMetricsObserver;

    // 创建缓存命中的 metrics 对象
    EMASCurlTransactionMetrics *cacheMetrics = [[EMASCurlTransactionMetrics alloc] init];
    cacheMetrics.fetchStartDate = self.fetchStartDate ?: [NSDate date];
    cacheMetrics.responseEndDate = [NSDate date];
    // 所有网络时间保持nil/0，表示无网络活动

    if (globalCallback) {
        globalCallback(self.request, YES, nil, cacheMetrics);
    }
    if (instanceCallback) {
        instanceCallback(self.request, YES, nil, cacheMetrics);
    }
    if (self.metricsObserverBlock) {
        self.metricsObserverBlock(self.request, YES, nil, 0, 0, 0, 0, 0, 0);
    }
}

// 使用 Manager 传入的 metrics 数据，避免访问已释放的 easyHandle
- (void)reportNetworkMetricWithData:(EMASCurlMetricsData *)metricsData success:(BOOL)success error:(NSError *)error {
    if (!metricsData) {
        NSError *fallbackError = error;
        if (!fallbackError) {
            fallbackError = [NSError errorWithDomain:@"EMASCurlProtocol"
                                                code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing metrics data from curl"}];
        }
        EMAS_LOG_ERROR(@"EC-Performance", @"Metrics data missing, reporting early failure: %@", fallbackError.localizedDescription);
        [self reportEarlyFailure:fallbackError];
        return;
    }

    // 从传入的数据对象中提取性能数据
    double nameLookupTime = metricsData.nameLookupTime;
    double connectTime = metricsData.connectTime;
    double appConnectTime = metricsData.appConnectTime;
    double preTransferTime = metricsData.preTransferTime;
    double startTransferTime = metricsData.startTransferTime;
    double totalTime = metricsData.totalTime;

    // 如果有自定义 DNS 解析时间，使用它
    if (self.resolveDomainTimeInterval > 0) {
        nameLookupTime = self.resolveDomainTimeInterval;
    }

    // 记录性能指标
    EMAS_LOG_INFO(@"EC-Performance", @"Request completed in %.0fms (DNS: %.0fms, Connect: %.0fms, Transfer: %.0fms) for URL: %@ (HTTP %ld)",
                  totalTime * 1000, nameLookupTime * 1000, connectTime * 1000, startTransferTime * 1000, 
                  self.request.URL.absoluteString, (long)self.currentResponse.statusCode);

    // 检查是否有全局综合性能指标回调
    EMASCurlTransactionMetricsObserverBlock globalTransactionCallback = nil;
    @synchronized ([EMASCurlProtocol class]) {
        globalTransactionCallback = globalTransactionMetricsObserverBlock;
    }

    // 检查是否有实例级别性能指标回调
    EMASCurlTransactionMetricsObserverBlock instanceTransactionCallback = self.resolvedConfiguration.transactionMetricsObserver;

    if (globalTransactionCallback || instanceTransactionCallback) {
        // 创建综合性能指标对象
        EMASCurlTransactionMetrics *transactionMetrics = [self createTransactionMetricsWithData:metricsData
                                                                                 nameLookupTime:nameLookupTime];

        if (globalTransactionCallback) {
            globalTransactionCallback(self.request, success, error, transactionMetrics);
        }
        if (instanceTransactionCallback) {
            instanceTransactionCallback(self.request, success, error, transactionMetrics);
        }
    }

    // 检查简单性能指标回调（向下兼容）
    if (self.metricsObserverBlock) {
        self.metricsObserverBlock(self.request,
                      success,
                      error,
                      nameLookupTime * 1000,
                      connectTime * 1000,
                      appConnectTime * 1000,
                      preTransferTime * 1000,
                      startTransferTime * 1000,
                      totalTime * 1000);
    }
}

// 使用 Manager 传入的 metrics 数据创建 TransactionMetrics，避免访问已释放的 easyHandle
- (EMASCurlTransactionMetrics *)createTransactionMetricsWithData:(EMASCurlMetricsData *)metricsData
                                                  nameLookupTime:(double)nameLookupTime {
    EMASCurlTransactionMetrics *metrics = [[EMASCurlTransactionMetrics alloc] init];

    double connectTime = metricsData.connectTime;
    double appConnectTime = metricsData.appConnectTime;
    double preTransferTime = metricsData.preTransferTime;
    double startTransferTime = metricsData.startTransferTime;
    double totalTime = metricsData.totalTime;

    // 计算时间戳（基于fetchStartDate）
    NSTimeInterval baseTime = self.fetchStartDate.timeIntervalSince1970;

    metrics.fetchStartDate = self.fetchStartDate;

    if (nameLookupTime > 0) {
        metrics.domainLookupStartDate = self.fetchStartDate;
        metrics.domainLookupEndDate = [NSDate dateWithTimeIntervalSince1970:baseTime + nameLookupTime];
    }

    if (connectTime > 0) {
        metrics.connectStartDate = [NSDate dateWithTimeIntervalSince1970:baseTime + nameLookupTime];
        metrics.connectEndDate = [NSDate dateWithTimeIntervalSince1970:baseTime + connectTime];
    }

    if (appConnectTime > 0) {
        metrics.secureConnectionStartDate = [NSDate dateWithTimeIntervalSince1970:baseTime + connectTime];
        metrics.secureConnectionEndDate = [NSDate dateWithTimeIntervalSince1970:baseTime + appConnectTime];
    }

    if (preTransferTime > 0) {
        metrics.requestStartDate = [NSDate dateWithTimeIntervalSince1970:baseTime + appConnectTime];
        metrics.requestEndDate = [NSDate dateWithTimeIntervalSince1970:baseTime + preTransferTime];
    }

    if (startTransferTime > 0) {
        metrics.responseStartDate = [NSDate dateWithTimeIntervalSince1970:baseTime + startTransferTime];
    }

    if (totalTime > 0) {
        metrics.responseEndDate = [NSDate dateWithTimeIntervalSince1970:baseTime + totalTime];
    }

    // 从传入的字典中填充额外信息
    [self populateTransactionMetricsFromData:metricsData metrics:metrics];

    // 自定义DNS解析信息
    metrics.usedCustomDNSResolverResult = self.usedCustomDNSResolverResult;

    return metrics;
}

// 使用传入的数据填充 metrics，避免访问已释放的 easyHandle
- (void)populateTransactionMetricsFromData:(EMASCurlMetricsData *)metricsData metrics:(EMASCurlTransactionMetrics *)metrics {
    // 获取HTTP版本信息
    switch (metricsData.httpVersion) {
        case CURL_HTTP_VERSION_1_0:
            metrics.networkProtocolName = @"http/1.0";
            break;
        case CURL_HTTP_VERSION_1_1:
            metrics.networkProtocolName = @"http/1.1";
            break;
        case CURL_HTTP_VERSION_2_0:
            metrics.networkProtocolName = @"http/2";
            break;
        case CURL_HTTP_VERSION_3:
            metrics.networkProtocolName = @"http/3";
            break;
        default:
            metrics.networkProtocolName = @"http/1.1";
            break;
    }

    // 获取连接信息
    metrics.reusedConnection = (metricsData.numConnects == 0);
    metrics.proxyConnection = metricsData.usedProxy;

    // 获取传输字节数
    metrics.requestHeaderBytesSent = metricsData.requestSize;
    metrics.responseHeaderBytesReceived = metricsData.headerSize;

    // 获取实际传输的字节数
    metrics.requestBodyBytesSent = metricsData.uploadBytes;
    metrics.responseBodyBytesReceived = metricsData.downloadBytes;

    // 获取网络地址信息
    if (metricsData.localIP.length > 0) {
        metrics.localAddress = metricsData.localIP;
    }
    metrics.localPort = metricsData.localPort;

    if (metricsData.primaryIP.length > 0) {
        metrics.remoteAddress = metricsData.primaryIP;
    }
    metrics.remotePort = metricsData.primaryPort;
}

#pragma mark * curl option setup

- (void)populateRequestHeader:(CURL *)easyHandle {
    NSURLRequest *request = self.request;

    // 配置HTTP METHOD
    if ([HTTP_METHOD_GET isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_HTTPGET, 1);
    } else if ([HTTP_METHOD_POST isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_POST, 1);
    } else if ([HTTP_METHOD_PUT isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_UPLOAD, 1);
    } else if ([HTTP_METHOD_HEAD isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_NOBODY, 1);
    } else {
        curl_easy_setopt(easyHandle, CURLOPT_CUSTOMREQUEST, [request.HTTPMethod UTF8String]);
    }

    // 配置URL
    curl_easy_setopt(easyHandle, CURLOPT_URL, request.URL.absoluteString.UTF8String);

    // 配置 http version
    HTTPVersion httpVersion = self.resolvedConfiguration.httpVersion;
    switch (httpVersion) {
        case HTTP3:
            // 仅https url能使用quic
            if (curlFeatureHttp3 && [request.URL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
                // Use HTTP/3, fallback to HTTP/2 or HTTP/1 if needed. For HTTPS only. For HTTP, this option makes libcurl return error.
                curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_3);
            } else if (curlFeatureHttp2) {
                // Attempt HTTP 2 requests. libcurl falls back to HTTP 1.1 if HTTP 2 cannot be negotiated with the server.
                curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2);
            } else {
                // 仅使用http1.1
                curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
            }
            break;
        case HTTP2:
            if (curlFeatureHttp2) {
                curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2);
            } else {
                curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
            }
            break;
        default:
            curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
            break;
    }

    // 将拦截到的request的header字段进行透传
    self.requestHeaderFields = [self convertHeadersToCurlSlist:request.allHTTPHeaderFields];

    // 检查是否手动设置了Accept-Encoding头部
    NSString *manualAcceptEncoding = [request valueForHTTPHeaderField:@"Accept-Encoding"];
    if (manualAcceptEncoding != nil) {
        // 用户手动设置了Accept-Encoding头部，完全尊重用户的意图
        // 即使是空字符串也表示用户明确要求不使用压缩
        NSString *trimmedEncoding = [manualAcceptEncoding stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (trimmedEncoding.length == 0) {
            // 用户设置了空的Accept-Encoding，明确禁用压缩
            EMAS_LOG_DEBUG(@"EC-Headers", @"Empty Accept-Encoding header detected, compression disabled by user");
            // 不设置CURLOPT_ACCEPT_ENCODING，即使s_enableBuiltInGzip为true
        } else {
            // 用户设置了非空的Accept-Encoding，过滤出支持的编码方法
            NSString *filteredEncoding = [self filterSupportedEncodings:trimmedEncoding];
            if (filteredEncoding.length > 0) {
                curl_easy_setopt(easyHandle, CURLOPT_ACCEPT_ENCODING, [filteredEncoding UTF8String]);
                EMAS_LOG_DEBUG(@"EC-Headers", @"Using filtered Accept-Encoding: %@", filteredEncoding);
            } else {
                // 如果过滤后没有支持的编码，则不设置压缩
                EMAS_LOG_DEBUG(@"EC-Headers", @"No supported encodings found in manual Accept-Encoding: %@", trimmedEncoding);
            }
        }
    } else if (self.resolvedConfiguration.enableBuiltInGzip) {
        // 用户没有手动设置Accept-Encoding头部，使用内置gzip设置
        curl_easy_setopt(easyHandle, CURLOPT_ACCEPT_ENCODING, "");
        EMAS_LOG_DEBUG(@"EC-Headers", @"Using built-in gzip encoding");
    }

    // 只对GET请求添加缓存相关条件头
    if (self.resolvedConfiguration.cacheEnabled && [[self.request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {
        // 再次从缓存获取，看是否有可用于条件GET的项
        // 注意：这里的 request 应该是用于网络请求的 NSMutableURLRequest
        // 而 s_responseCache.cachedResponseForRequest 需要原始的 self.request (或其副本) 作为键
        NSCachedURLResponse *cachedResponse = [s_responseCache cachedResponseForRequest:self.request];

        // cachedResponseForRequest 返回的要么是nil，要么是新鲜/可验证的
        if (cachedResponse) {
            BOOL isFresh = [cachedResponse emas_isResponseStillFreshForRequest:self.request]; // 再次检查，考虑请求头
            BOOL requiresRevalidation = [cachedResponse emas_requiresRevalidation];

            // 只有当响应不是新鲜的，或者它新鲜但服务器要求重新验证(no-cache)时，才添加条件头
            if (!isFresh || requiresRevalidation) {
                NSString *etag = [cachedResponse emas_etag];
                if (etag) {
                    // 在这里，你需要将头添加到实际要发送的请求对象 (可能是 mutableRequest)
                    // 例如: [mutableRequest setValue:etag forHTTPHeaderField:@"If-None-Match"];
                    // 下面的 curl_slist_append 逻辑需要适配你的 libcurl 请求构建过程
                    NSString *ifNoneMatchHeaderValue = etag; // ETag本身就是值
                    self.requestHeaderFields = curl_slist_append(self.requestHeaderFields, [[NSString stringWithFormat:@"If-None-Match: %@", ifNoneMatchHeaderValue] UTF8String]);
                }

                NSString *lastModified = [cachedResponse emas_lastModified];
                if (lastModified) {
                    // 例如: [mutableRequest setValue:lastModified forHTTPHeaderField:@"If-Modified-Since"];
                    NSString *ifModifiedSinceHeaderValue = lastModified; // Last-Modified本身就是值
                    self.requestHeaderFields = curl_slist_append(self.requestHeaderFields, [[NSString stringWithFormat:@"If-Modified-Since: %@", ifModifiedSinceHeaderValue] UTF8String]);
                }
            }
        }
    }

    curl_easy_setopt(easyHandle, CURLOPT_HTTPHEADER, self.requestHeaderFields);
}

- (void)populateRequestBody:(CURL *)easyHandle {
    NSURLRequest *request = self.request;

    if (!request.HTTPBodyStream) {
        if ([HTTP_METHOD_PUT isEqualToString:request.HTTPMethod]) {
            curl_easy_setopt(easyHandle, CURLOPT_INFILESIZE_LARGE, 0L);
        } else if ([HTTP_METHOD_POST isEqualToString:request.HTTPMethod]) {
            curl_easy_setopt(easyHandle, CURLOPT_POSTFIELDSIZE_LARGE, 0L);
        } else {
            // 其他情况无需处理
        }

        return;
    }

    // NSURLSession内部会把HTTPBody统一转换到HTTPBodyStream，因此不用单独处理HTTPBody字段
    self.inputStream = request.HTTPBodyStream;

    // 用read_cb回调函数来读取需要传输的数据
    curl_easy_setopt(easyHandle, CURLOPT_READFUNCTION, read_cb);
    // self传给read_cb函数的void *userp参数
    curl_easy_setopt(easyHandle, CURLOPT_READDATA, (__bridge void *)self);

    if ([HTTP_METHOD_PATCH isEqualToString:request.HTTPMethod]
        || [HTTP_METHOD_DELETE isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_UPLOAD, 1);
    }

    NSString *contentLength = [request valueForHTTPHeaderField:@"Content-Length"];
    if (!contentLength) {
        // chunked模式不发送Expect，保持和NSURLSession的行为一致
        self.requestHeaderFields = curl_slist_append(self.requestHeaderFields, "Expect:");
        // 未设置Content-Length的情况，即使是使用Transfer-Encoding: chunked，也把totalBytesExpected设置为-1
        self.totalBytesExpected = -1;
        return;
    }

    int64_t length = [contentLength longLongValue];
    self.totalBytesExpected = length;

    if ([HTTP_METHOD_PUT isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_INFILESIZE_LARGE, length);
        return;
    }

    if ([HTTP_METHOD_GET isEqualToString:request.HTTPMethod]
        || [HTTP_METHOD_HEAD isEqualToString:request.HTTPMethod]) {
        // GET/HEAD方法不需要设置body
        return;
    }

    // 其他情况，都以POST的方式指定Content-Length
    curl_easy_setopt(easyHandle, CURLOPT_POSTFIELDSIZE_LARGE, length);
}

- (void)configEasyHandle:(CURL *)easyHandle error:(NSError **)error {
    // 假如是quic这个framework，由于使用的boringssl无法访问苹果native CA，需要从Bundle中读取CA
    if (curlFeatureHttp3) {
        NSBundle *frameworkBundle = [NSBundle bundleForClass:[self class]];
        NSURL *bundleURL = [frameworkBundle URLForResource:@"EMASCAResource" withExtension:@"bundle"];
        if (!bundleURL) {
            *error = [NSError errorWithDomain:@"fail to load CA certificate." code:-3 userInfo:nil];
            return;
        }
        NSBundle *resourceBundle = [NSBundle bundleWithURL:bundleURL];
        NSString *filePath = [resourceBundle pathForResource:@"cacert" ofType:@"pem"];
        curl_easy_setopt(easyHandle, CURLOPT_CAINFO, [filePath UTF8String]);
    }

    // 是否设置自定义根证书
    if (self.resolvedConfiguration.caFilePath) {
        curl_easy_setopt(easyHandle, CURLOPT_CAINFO, [self.resolvedConfiguration.caFilePath UTF8String]);
    }

    // 配置证书校验
    if (self.resolvedConfiguration.certificateValidationEnabled) {
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYPEER, 1L);
    } else {
        EMAS_LOG_INFO(@"EC-SSL", @"Certificate validation disabled");
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYPEER, 0L);
    }

    // 配置域名校验
    // 0: 不校验域名
    // 1: 校验域名是否存在于证书中，但仅用于提示 (libcurl < 7.28.0)
    // 2: 校验域名是否存在于证书中且匹配 (libcurl >= 7.28.0 推荐)
    if (self.resolvedConfiguration.domainNameVerificationEnabled) {
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYHOST, 2L);
    } else {
        EMAS_LOG_INFO(@"EC-SSL", @"Domain name verification disabled");
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYHOST, 0L);
    }

    // 设置公钥固定
    if (self.resolvedConfiguration.publicKeyPinningKeyPath) {
        EMAS_LOG_INFO(@"EC-SSL", @"Using public key pinning for host: %@", self.request.URL.host);
        curl_easy_setopt(easyHandle, CURLOPT_PINNEDPUBLICKEY, [self.resolvedConfiguration.publicKeyPinningKeyPath UTF8String]);
    }

    NSString *proxyServer = nil;
    if (self.resolvedConfiguration.proxyServer.length > 0) {
        // 若显式配置了代理地址，则无条件使用该代理
        proxyServer = self.resolvedConfiguration.proxyServer;
    } else {
        proxyServer = [EMASCurlProxySetting proxyServerForURL:self.request.URL];
    }

    // 无代理时才需要提前解析域名
    BOOL shouldRequestDirectly = (proxyServer.length == 0);
    if (self.resolvedConfiguration.dnsResolver && shouldRequestDirectly) {
        NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
        if ([self preResolveDomain:easyHandle]) {
            self.resolveDomainTimeInterval = [[NSDate date] timeIntervalSince1970] - startTime;
            self.usedCustomDNSResolverResult = YES;
        }
    }

    // 设置cookie
    EMASCurlCookieStorage *cookieStorage = [EMASCurlCookieStorage sharedStorage];
    NSString *cookieString = [cookieStorage cookieStringForURL:self.request.URL];
    if (cookieString) {
        curl_easy_setopt(easyHandle, CURLOPT_COOKIE, [cookieString UTF8String]);
    }

    if (proxyServer.length > 0) {
        curl_easy_setopt(easyHandle, CURLOPT_PROXY, [proxyServer UTF8String]);
        EMAS_LOG_INFO(@"EC-Proxy", @"Using proxy: %@", proxyServer);
    } else {
        EMAS_LOG_DEBUG(@"EC-Proxy", @"No proxy configured");
    }

    // 设置debug回调函数以输出日志
    // 注意：日志级别保持全局配置
    if ([EMASCurlLogger currentLogLevel] >= EMASCurlLogLevelDebug) {
        curl_easy_setopt(easyHandle, CURLOPT_VERBOSE, 1L);
        curl_easy_setopt(easyHandle, CURLOPT_DEBUGFUNCTION, debug_cb);
    }

    // 设置header回调函数处理收到的响应的header数据
    // receivedHeader会被传给header_cb函数的void *userp参数
    curl_easy_setopt(easyHandle, CURLOPT_HEADERFUNCTION, header_cb);
    curl_easy_setopt(easyHandle, CURLOPT_HEADERDATA, (__bridge void *)self);

    // 设置write回调函数处理收到的响应的body数据
    // self会被传给write_cb函数的void *userp
    curl_easy_setopt(easyHandle, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(easyHandle, CURLOPT_WRITEDATA, (__bridge void *)self);

    // 设置progress_callback以响应任务取消
    curl_easy_setopt(easyHandle, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(easyHandle, CURLOPT_XFERINFOFUNCTION, progress_callback);
    curl_easy_setopt(easyHandle, CURLOPT_XFERINFODATA, (__bridge void *)self);

    // 开启TCP keep alive
    curl_easy_setopt(easyHandle, CURLOPT_TCP_KEEPALIVE, 1L);

    // 设置连接超时时间
    NSNumber *connectTimeoutInterval = [NSURLProtocol propertyForKey:(NSString *)kEMASCurlConnectTimeoutIntervalKey inRequest:self.request];
    NSTimeInterval connectTimeout;
    if (connectTimeoutInterval) {
        // 使用请求级别的连接超时设置
        connectTimeout = connectTimeoutInterval.doubleValue;
        EMAS_LOG_DEBUG(@"EC-Timeout", @"Using per-request connect timeout: %.1f seconds", connectTimeout);
    } else {
        // 使用配置中的连接超时设置
        connectTimeout = self.resolvedConfiguration.connectTimeoutInterval;
    }
    curl_easy_setopt(easyHandle, CURLOPT_CONNECTTIMEOUT_MS, (long)(connectTimeout * 1000));

    // 设置请求超时时间（空闲超时模式）
    // 使用 LOW_SPEED_LIMIT + LOW_SPEED_TIME 模拟空闲超时
    NSTimeInterval requestTimeoutInterval = self.request.timeoutInterval;
    if (requestTimeoutInterval > 0) {
        curl_easy_setopt(easyHandle, CURLOPT_LOW_SPEED_LIMIT, 1L);
        curl_easy_setopt(easyHandle, CURLOPT_LOW_SPEED_TIME, (long)requestTimeoutInterval);
    }

    // 开启重定向
    if (self.resolvedConfiguration.enableBuiltInRedirection) {
        curl_easy_setopt(easyHandle, CURLOPT_FOLLOWLOCATION, 1L);
    } else {
        curl_easy_setopt(easyHandle, CURLOPT_FOLLOWLOCATION, 0L);
    }

    // 为了线程安全，设置NOSIGNAL
    curl_easy_setopt(easyHandle, CURLOPT_NOSIGNAL, 1L);
}

- (BOOL)preResolveDomain:(CURL *)easyHandle {
    NSURL *url = self.request.URL;
    if (!url || !url.host) {
        return NO;
    }

    NSString *host = url.host;
    NSNumber *port = url.port;
    NSString *scheme = url.scheme.lowercaseString;

    NSInteger resolvedPort;
    if (port) {
        resolvedPort = port.integerValue;
    } else {
        if ([scheme isEqualToString:@"https"]) {
            resolvedPort = 443;
        } else if ([scheme isEqualToString:@"http"]) {
            resolvedPort = 80;
        } else {
            return NO;
        }
    }

    EMAS_LOG_INFO(@"EC-DNS", @"Using custom DNS resolver for domain: %@", host);

    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    NSString *address = [self.resolvedConfiguration.dnsResolver resolveDomain:host];
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();

    double resolutionTime = (endTime - startTime) * 1000; // 转换为毫秒
    self.resolveDomainTimeInterval = resolutionTime;

    if (!address) {
        EMAS_LOG_ERROR(@"EC-DNS", @"Custom DNS resolver returned nil for domain: %@", host);
        return NO;
    }

    EMAS_LOG_DEBUG(@"EC-DNS", @"Resolved %@ to IPs: %@", host, address);
    EMAS_LOG_DEBUG(@"EC-DNS", @"DNS resolution took %.2fms", resolutionTime);

    // Format: +{host}:{port}:{ips}
    NSString *hostPortAddressString = [NSString stringWithFormat:@"+%@:%ld:%@",
                                     host,
                                     (long)resolvedPort,
                                     address];

    self.resolveList = curl_slist_append(self.resolveList, [hostPortAddressString UTF8String]);
    if (self.resolveList) {
        curl_easy_setopt(easyHandle, CURLOPT_RESOLVE, self.resolveList);
        return YES;
    }
    return NO;
}

// 过滤Accept-Encoding头部，只保留libcurl支持的编码方法（gzip和deflate）
- (NSString *)filterSupportedEncodings:(NSString *)acceptEncoding {
    if (!acceptEncoding || acceptEncoding.length == 0) {
        return nil;
    }

    // libcurl支持的编码方法
    NSSet *supportedEncodings = [NSSet setWithObjects:@"gzip", @"deflate", @"identity", nil];

    // 解析Accept-Encoding头部值
    NSArray *encodings = [acceptEncoding componentsSeparatedByString:@","];
    NSMutableArray *filteredEncodings = [NSMutableArray array];

    for (NSString *encoding in encodings) {
        // 清理每个编码值（去除空格和质量值）
        NSString *cleanEncoding = [encoding stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // 如果包含质量值（如 "gzip;q=0.8"），只取编码名称部分
        NSRange semicolonRange = [cleanEncoding rangeOfString:@";"];
        if (semicolonRange.location != NSNotFound) {
            cleanEncoding = [cleanEncoding substringToIndex:semicolonRange.location];
            cleanEncoding = [cleanEncoding stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }

        // 检查是否为支持的编码
        if ([supportedEncodings containsObject:cleanEncoding.lowercaseString]) {
            [filteredEncodings addObject:encoding]; // 保留原始格式（包括质量值）
        } else {
            EMAS_LOG_DEBUG(@"EC-Headers", @"Filtering out unsupported encoding: %@", cleanEncoding);
        }
    }

    if (filteredEncodings.count == 0) {
        return nil;
    }

    return [filteredEncodings componentsJoinedByString:@","];
}

// 将拦截到的request中的header字段，转换为一个curl list
- (struct curl_slist *)convertHeadersToCurlSlist:(NSDictionary<NSString *, NSString *> *)headers {
    struct curl_slist *headerFields = NULL;
    BOOL userAgentPresent = NO; // 标记User-Agent是否存在

    for (NSString *key in headers) {
        // 对于Content-Length，使用CURLOPT_POSTFIELDSIZE_LARGE指定，不要在这里透传，否则POST重定向为GET时仍会保留Content-Length，导致错误
        if ([key caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame) {
            continue;
        }
        // 对于Accept-Encoding，已经在populateRequestHeader中单独处理了，这里跳过避免重复设置
        if ([key caseInsensitiveCompare:@"Accept-Encoding"] == NSOrderedSame) {
            continue;
        }
        // 跳过内部配置头，不发送给服务器
        if ([key caseInsensitiveCompare:kEMASCurlConfigurationHeaderKey] == NSOrderedSame) {
            continue;
        }
        // 检查是否已提供User-Agent
        if ([key caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
            userAgentPresent = YES;
        }

        NSString *value = headers[key];
        NSString *header;
        if ([[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] == 0) {
            header = [NSString stringWithFormat:@"%@;", key];
        } else {
            header = [NSString stringWithFormat:@"%@: %@", key, value];
        }
        headerFields = curl_slist_append(headerFields, [header UTF8String]);
    }

    // 如果没有提供User-Agent，则添加默认的
    if (!userAgentPresent) {
        NSString *defaultUAHeader = [NSString stringWithFormat:@"User-Agent: %@", [NSString stringWithFormat:@"EMASCurl/%@", EMASCURL_SDK_VERSION]];
        headerFields = curl_slist_append(headerFields, [defaultUAHeader UTF8String]);
    }

    // 携带版本信息的自定义头
    NSString *verHeader = [NSString stringWithFormat:@"x-emascurl-version: %@", EMASCURL_SDK_VERSION];
    headerFields = curl_slist_append(headerFields, [verHeader UTF8String]);

    return headerFields;
}

#pragma mark * libcurl callback function

// libcurl的header回调函数，用于处理收到的header
size_t header_cb(char *buffer, size_t size, size_t nitems, void *userdata) {
    EMASCurlProtocol *protocol = (__bridge EMASCurlProtocol *)userdata;

    size_t totalSize = size * nitems;
    NSData *data = [NSData dataWithBytes:buffer length:size * nitems];

    NSString *headerLine = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!headerLine) {
        return totalSize;
    }

    headerLine = [headerLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([headerLine hasPrefix:@"HTTP/"]) {
        // 头部首行，标识新的头部开始
        [protocol.currentResponse reset];

        NSArray<NSString *> *components = [headerLine componentsSeparatedByString:@" "];
        if (components.count >= 3) {
            protocol.currentResponse.httpVersion = components[0];
            protocol.currentResponse.statusCode = [components[1] integerValue];
            protocol.currentResponse.reasonPhrase = [[components subarrayWithRange:NSMakeRange(2, components.count - 2)] componentsJoinedByString:@" "];
        } else if (components.count == 2) {
            protocol.currentResponse.httpVersion = components[0];
            protocol.currentResponse.statusCode = [components[1] integerValue];
            protocol.currentResponse.reasonPhrase = @"";
        }

        EMAS_LOG_INFO(@"EC-Response", @"Received response: %ld %@", (long)protocol.currentResponse.statusCode, protocol.currentResponse.reasonPhrase);
        EMAS_LOG_DEBUG(@"EC-Response", @"Processing %@ response", protocol.currentResponse.httpVersion);
    } else {
        NSRange delimiterRange = [headerLine rangeOfString:@": "];
        if (delimiterRange.location != NSNotFound) {
            NSString *key = [headerLine substringToIndex:delimiterRange.location];
            NSString *value = [headerLine substringFromIndex:delimiterRange.location + delimiterRange.length];

            if (!key) {
                // key不能为空，否则无法处理
                return totalSize;
            }
            if (!value) {
                value = @"";
            }

            // 设置cookie
            if ([key caseInsensitiveCompare:@"set-cookie"] == NSOrderedSame) {
                EMASCurlCookieStorage *cookieStorage = [EMASCurlCookieStorage sharedStorage];
                [cookieStorage setCookieWithString:value forURL:protocol.request.URL];
                EMAS_LOG_DEBUG(@"EC-Response", @"Cookie set: %@", value);
            }

            if (protocol.currentResponse.headers[key]) {
                NSString *existingValue = protocol.currentResponse.headers[key];
                NSString *combinedValue = [existingValue stringByAppendingFormat:@", %@", value];
                protocol.currentResponse.headers[key] = combinedValue;
            } else {
                protocol.currentResponse.headers[key] = value;
            }
        }
    }

    if ([headerLine length] == 0) {
        // 尾行，标识当前头部读取结束
        NSInteger statusCode = protocol.currentResponse.statusCode;
        NSString *reasonPhrase = protocol.currentResponse.reasonPhrase;

        // 处理304 Not Modified响应
        if (statusCode == 304 && protocol.resolvedConfiguration.cacheEnabled) {
            // 更新缓存并获取更新后的响应
            NSCachedURLResponse *updatedResponse = [s_responseCache updateCachedResponseWithHeaders:protocol.currentResponse.headers
                                                                                         forRequest:protocol.request];
            if (updatedResponse) {
                [protocol invokeOnClientThread:^{
                    if (![protocol hasClientNotified]) {
                        [protocol.client URLProtocol:protocol didReceiveResponse:updatedResponse.response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                        [protocol.client URLProtocol:protocol didLoadData:updatedResponse.data];
                    }
                }];
                return totalSize;
            }
        }

        NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:protocol.request.URL
                                                                      statusCode:protocol.currentResponse.statusCode
                                                                     HTTPVersion:protocol.currentResponse.httpVersion
                                                                    headerFields:protocol.currentResponse.headers];
        if (isRedirectionStatusCode(statusCode)) {
            if (!protocol.resolvedConfiguration.enableBuiltInRedirection) {
                // 关闭了重定向支持，则把重定向信息往外传递
                __block NSString *location = nil;
                [protocol.currentResponse.headers enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
                    if ([key caseInsensitiveCompare:@"Location"] == NSOrderedSame) {
                        location = obj;
                        *stop = YES;
                    }
                }];
                if (location) {
                    EMAS_LOG_DEBUG(@"EC-Response", @"Handling redirect to: %@", location);
                    NSURL *locationURL = [NSURL URLWithString:location relativeToURL:protocol.request.URL];
                    NSMutableURLRequest *redirectedRequest = [protocol.request mutableCopy];
                    [NSURLProtocol removePropertyForKey:kEMASCurlHandledKey inRequest:redirectedRequest];
                    [redirectedRequest setURL:locationURL];
                    [protocol invokeOnClientThread:^{
                        if (![protocol hasClientNotified]) {
                            [protocol.client URLProtocol:protocol wasRedirectedToRequest:redirectedRequest redirectResponse:httpResponse];
                        }
                    }];
                }
            }
            [protocol.currentResponse reset];
        } else if (isInformationalStatusCode(statusCode)) {
            [protocol.currentResponse reset];
        } else if (isConnectEstablishedStatusCode(statusCode, reasonPhrase)) {
            [protocol.currentResponse reset];
        } else {
            [protocol invokeOnClientThread:^{
                if (![protocol hasClientNotified]) {
                    [protocol.client URLProtocol:protocol didReceiveResponse:httpResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                }
            }];
            protocol.currentResponse.isFinalResponse = YES;

            // 仅在最终响应首包前决定是否在内存中缓冲以用于缓存。
            // 复杂原因：若无上限，巨大GET响应会导致NSMutableData反复扩容，引发NSMallocException。
            if (protocol.resolvedConfiguration.cacheEnabled &&
                [[protocol.request.HTTPMethod uppercaseString] isEqualToString:@"GET"] &&
                isPotentiallyCacheableStatusCode(statusCode)) {
                // 检查Cache-Control: no-store，遇到则不缓冲
                NSString *cacheCtl = protocol.currentResponse.headers[@"Cache-Control"] ?: protocol.currentResponse.headers[@"cache-control"];
                BOOL hasNoStore = NO;
                if (cacheCtl.length > 0) {
                    NSString *lc = [cacheCtl lowercaseString];
                    hasNoStore = [lc containsString:@"no-store"];
                }

                if (!hasNoStore) {
                    protocol.shouldBufferBodyForCache = YES;

                    // 依据Content-Length和阈值预判是否值得在内存中缓冲
                    NSString *clStr = protocol.currentResponse.headers[@"Content-Length"] ?: protocol.currentResponse.headers[@"content-length"];
                    unsigned long long contentLen = (unsigned long long) [clStr longLongValue];
                    NSUInteger cap = (NSUInteger)MIN(contentLen > 0 ? contentLen : 0, protocol.resolvedConfiguration.maximumCacheableBodyBytes);

                    if (contentLen > 0 && contentLen > protocol.resolvedConfiguration.maximumCacheableBodyBytes) {
                        // 预判超过阈值，直接放弃缓冲，避免后续appendData内存暴涨
                        protocol.shouldBufferBodyForCache = NO;
                        protocol.receivedResponseData = nil;
                        protocol.bufferedCacheBytes = 0;
                    } else {
                        if (cap > 0) {
                            protocol.receivedResponseData = [NSMutableData dataWithCapacity:cap];
                        } else {
                            // 保留已有对象，但仍受后续增量检查限制
                            if (!protocol.receivedResponseData) {
                                protocol.receivedResponseData = [NSMutableData new];
                            }
                        }
                    }
                }
            }
        }
    }

    return totalSize;
}

BOOL isRedirectionStatusCode(NSInteger statusCode) {
    switch (statusCode) {
        case 300: // Multiple Choices
        case 301: // Moved Permanently
        case 302: // Found
        case 303: // See Other
        case 307: // Temporary Redirect
        case 308: // Permanent Redirect
            return YES;
        default:
            return NO;
    }
}

BOOL isInformationalStatusCode(NSInteger statusCode) {
    return statusCode >= 100 && statusCode < 200;
}

BOOL isConnectEstablishedStatusCode(NSInteger statusCode, NSString *reasonPhrase) {
    return statusCode == 200 && [reasonPhrase caseInsensitiveCompare:@"connection established"] == NSOrderedSame;
}

// libcurl的write回调函数，用于处理收到的body
static size_t write_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    EMASCurlProtocol *protocol = (__bridge EMASCurlProtocol *)userp;

    size_t totalSize = size * nmemb;
    NSData *data = [[NSData alloc] initWithBytes:contents length:totalSize];

    // 收集响应数据用于缓存（带内存上限保护）
    if (protocol.shouldBufferBodyForCache) {
        NSUInteger limit = protocol.resolvedConfiguration.maximumCacheableBodyBytes;
        if (protocol.bufferedCacheBytes + totalSize <= limit) {
            [protocol.receivedResponseData appendData:data];
            protocol.bufferedCacheBytes += totalSize;
        } else {
            // 超过阈值，停止继续缓冲并释放已占用的缓冲，避免持续膨胀
            // 中文注释（复杂逻辑）：一旦发现累计大小超过配置阈值，立即放弃内存缓存，释放已缓存数据，后续不再尝试缓存，保证内存峰值受控。
            protocol.shouldBufferBodyForCache = NO;
            protocol.receivedResponseData = nil;
            protocol.bufferedCacheBytes = 0;
        }
    }

    // 只有确认获得已经读取了最后一个响应，接受的数据才视为有效数据
    if (protocol.currentResponse.isFinalResponse) {
        // 将客户端回调切回协议调度线程
        [protocol invokeOnClientThread:^{
            if (![protocol hasClientNotified]) {
                [protocol.client URLProtocol:protocol didLoadData:data];
            }
        }];
    }

    return totalSize;
}

// libcurl的read回调函数，用于post等需要设置body数据的方法
static size_t read_cb(char *buffer, size_t size, size_t nitems, void *userp) {
    EMASCurlProtocol *protocol = (__bridge EMASCurlProtocol *)userp;

    if (!protocol || !protocol.inputStream) {
        return CURL_READFUNC_ABORT;
    }

    if (protocol.shouldCancel) {
        return CURL_READFUNC_ABORT;
    }

    if ([protocol.inputStream streamStatus] == NSStreamStatusNotOpen) {
        [protocol.inputStream open];
    }

    NSInteger bytesRead = [protocol.inputStream read:(uint8_t *)buffer maxLength:size * nitems];
    if (bytesRead < 0) {
        return CURL_READFUNC_ABORT;
    }

    protocol.totalBytesSent += bytesRead;

    if (protocol.uploadProgressUpdateBlock) {
        protocol.uploadProgressUpdateBlock(protocol.request,
                                           bytesRead,
                                           protocol.totalBytesSent,
                                           protocol.totalBytesExpected);
    }

    return bytesRead;
}

static int progress_callback(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow) {
    EMASCurlProtocol *protocol = (__bridge EMASCurlProtocol *)clientp;
    // 检查是否取消传输
    if (protocol.shouldCancel) {
        return 1;
    }
    return 0;
}

// libcurl的debug回调函数，输出libcurl的运行日志
static int debug_cb(CURL *handle, curl_infotype type, char *data, size_t size, void *userptr) {
    // 只在Debug级别下记录libcurl详细信息
    if ([EMASCurlLogger currentLogLevel] < EMASCurlLogLevelDebug) {
        return 0;
    }

    // 创建NSString从数据，确保不包含换行符
    NSString *message = [[NSString alloc] initWithBytes:data length:size encoding:NSUTF8StringEncoding];
    if (!message) {
        return 0;
    }

    // 移除末尾的换行符
    message = [message stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    switch (type) {
        case CURLINFO_TEXT:
            EMAS_LOG_DEBUG(@"EC-libcurl", @"TEXT: %@", message);
            break;
        case CURLINFO_HEADER_IN:
            EMAS_LOG_DEBUG(@"EC-libcurl", @"HEADER_IN: %@", message);
            break;
        case CURLINFO_HEADER_OUT:
            EMAS_LOG_DEBUG(@"EC-libcurl", @"HEADER_OUT: %@", message);
            break;
        case CURLINFO_DATA_IN:
            EMAS_LOG_DEBUG(@"EC-libcurl", @"DATA_IN: %lu bytes", (unsigned long)size);
            break;
        case CURLINFO_DATA_OUT:
            EMAS_LOG_DEBUG(@"EC-libcurl", @"DATA_OUT: %lu bytes", (unsigned long)size);
            break;
        case CURLINFO_SSL_DATA_IN:
            EMAS_LOG_DEBUG(@"EC-libcurl", @"SSL_DATA_IN: %lu bytes", (unsigned long)size);
            break;
        case CURLINFO_SSL_DATA_OUT:
            EMAS_LOG_DEBUG(@"EC-libcurl", @"SSL_DATA_OUT: %lu bytes", (unsigned long)size);
            break;
        case CURLINFO_END:
            EMAS_LOG_DEBUG(@"EC-libcurl", @"END: %@", message);
            break;
        default:
            break;
    }
    return 0;
}

#pragma mark - 日志相关方法

+ (void)setLogLevel:(EMASCurlLogLevel)logLevel {
    [EMASCurlLogger setLogLevel:logLevel];
    // 同步更新旧的debug标志，保持一致性
    s_enableDebugLog = (logLevel >= EMASCurlLogLevelDebug);
}

+ (EMASCurlLogLevel)currentLogLevel {
    return [EMASCurlLogger currentLogLevel];
}

+ (void)setLogHandler:(nullable EMASCurlLogHandlerBlock)handler {
    [EMASCurlLogger setLogHandler:handler];
}

@end

#pragma mark - 调度线程封装与清理

@implementation EMASCurlProtocol (ClientThreading)

- (void)_invokeBlockOnClientThread:(dispatch_block_t)block {
    if (block) {
        block();
    }
}

- (void)invokeOnClientThread:(dispatch_block_t)block {
    if (!block) {
        return;
    }
    if ([NSThread currentThread] == self.clientThread) {
        block();
        return;
    }
    // 必须在协议调度线程/RunLoop模式下执行所有 client 回调，避免CFNetwork内部状态被跨线程访问导致竞态
    [self performSelector:@selector(_invokeBlockOnClientThread:)
                 onThread:self.clientThread
               withObject:[block copy]
            waitUntilDone:NO
                    modes:(self.clientRunLoopModes.count > 0 ? self.clientRunLoopModes : @[NSDefaultRunLoopMode])];
}

- (BOOL)markClientNotifiedIfNeeded {
    @synchronized (self) {
        if (self.clientNotified) {
            return NO;
        }
        self.clientNotified = YES;
        return YES;
    }
}

- (BOOL)hasClientNotified {
    @synchronized (self) {
        return self.clientNotified;
    }
}

- (void)cleanupIfNeeded {
    @synchronized (self) {
        if (self.cleanedUp) {
            return;
        }
        self.cleanedUp = YES;
    }
    // easy 句柄的销毁必须在被从 multi handle 移除后再执行；改为由 Manager 统一 cleanup，避免并发销毁
    if (self.inputStream) {
        if ([self.inputStream streamStatus] == NSStreamStatusOpen) {
            [self.inputStream close];
        }
        self.inputStream = nil;
    }
    if (self.requestHeaderFields) {
        curl_slist_free_all(self.requestHeaderFields);
        self.requestHeaderFields = nil;
    }
    if (self.resolveList) {
        curl_slist_free_all(self.resolveList);
        self.resolveList = nil;
    }
    // easyHandle 由 Manager 在 curl_multi_remove_handle 之后统一 curl_easy_cleanup
    self.easyHandle = nil;
}

@end

#pragma mark - 多实例配置支持

@implementation EMASCurlProtocol (MultiInstance)

+ (void)installIntoSessionConfiguration:(NSURLSessionConfiguration *)sessionConfig
                       withConfiguration:(EMASCurlConfiguration *)curlConfig {
    if (!sessionConfig || !curlConfig) {
        EMAS_LOG_ERROR(@"EC-MultiInstance", @"Cannot install: nil session or configuration");
        return;
    }

    // 生成唯一的配置ID
    NSString *configID = [[NSUUID UUID] UUIDString];

    // 将配置存储到管理器
    [[EMASCurlConfigurationManager sharedManager] setConfiguration:curlConfig forID:configID];

    // 将配置ID注入到session的HTTPAdditionalHeaders中
    NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:sessionConfig.HTTPAdditionalHeaders ?: @{}];
    headers[kEMASCurlConfigurationHeaderKey] = configID;
    sessionConfig.HTTPAdditionalHeaders = headers;

    // 安装protocol到session
    NSMutableArray *protocolsArray = [NSMutableArray arrayWithArray:sessionConfig.protocolClasses];
    [protocolsArray insertObject:self atIndex:0];
    [sessionConfig setProtocolClasses:protocolsArray];

    EMAS_LOG_INFO(@"EC-MultiInstance", @"Installed configuration %@ into session", configID);
}

+ (EMASCurlConfiguration *)defaultConfiguration {
    return [[EMASCurlConfigurationManager sharedManager] defaultConfiguration];
}

@end
