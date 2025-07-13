//
//  EMASCurlProtocol.m
//  EMASCurl
//
//  Created by xin yu on 2024/10/29.
//

#import "EMASCurlProtocol.h"
#import "EMASCurlConfiguration.h"
#import "EMASCurlManager.h"
#import "EMASCurlCookieStorage.h"
#import "EMASCurlResponseCache.h"
#import "NSCachedURLResponse+EMASCurl.h"
#import "EMASCurlLogger.h"
#import <curl/curl.h>
#import <objc/runtime.h>

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

// 关联对象的key常量
static const void *kEMASCurlConfigurationKey = &kEMASCurlConfigurationKey;
static const void *kEMASCurlWrapperKey = &kEMASCurlWrapperKey;

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

// 会话配置包装器，用于管理动态类的生命周期
@interface EMASCurlSessionConfigurationWrapper : NSObject

@property (nonatomic, assign) Class dynamicClass;

- (instancetype)initWithDynamicClass:(Class)dynamicClass;

@end

@implementation EMASCurlSessionConfigurationWrapper

- (instancetype)initWithDynamicClass:(Class)dynamicClass {
    self = [super init];
    if (self) {
        _dynamicClass = dynamicClass;
    }
    return self;
}

- (void)dealloc {
    // 当sessionConfiguration被释放时，自动清理动态类
    if (_dynamicClass) {
        // 调用EMASCurlProtocol的类方法来进行清理
        [EMASCurlProtocol cleanupDynamicClass:_dynamicClass];

        EMAS_LOG_DEBUG(@"EC-Memory", @"Cleaned up dynamic class: %@", NSStringFromClass(_dynamicClass));
    }
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

@property (nonatomic, strong) NSMutableData *receivedResponseData;

// Configuration for this protocol instance
@property (nonatomic, strong) EMASCurlConfiguration *configuration;

@end

// runtime 的libcurl xcframework是否支持HTTP2
static bool curlFeatureHttp2;

// runtime 的libcurl xcframework是否支持HTTP3
static bool curlFeatureHttp3;

// 基础设施组件 - 保持静态变量
static NSString *s_proxyServer;
static dispatch_queue_t s_serialQueue;
static dispatch_queue_t s_cacheQueue;
static EMASCurlResponseCache *s_responseCache;

// 代理管理
static BOOL s_manualProxyEnabled;
static NSTimer *s_proxyUpdateTimer;

// 全局配置对象 - 替代分散的静态变量
static EMASCurlConfiguration *s_globalConfiguration;

@implementation EMASCurlProtocol

#pragma mark * user API

#pragma mark - New Configuration-based API

+ (void)installIntoSessionConfiguration:(nonnull NSURLSessionConfiguration*)sessionConfiguration
                          configuration:(nonnull EMASCurlConfiguration *)configuration {
    // 为每个session创建唯一的协议子类
    static NSUInteger classCounter = 0;
    NSString *className = [NSString stringWithFormat:@"EMASCurlProtocol_%lu", (unsigned long)++classCounter];

    Class dynamicClass = objc_allocateClassPair([EMASCurlProtocol class], [className UTF8String], 0);
    if (!dynamicClass) {
        // 如果类创建失败，回退到全局配置方式
        NSMutableArray *protocolsArray = [NSMutableArray arrayWithArray:sessionConfiguration.protocolClasses];
        [protocolsArray insertObject:self atIndex:0];
        [sessionConfiguration setProtocolClasses:protocolsArray];
        return;
    }

    objc_registerClassPair(dynamicClass);

    // 直接将配置关联到动态类
    objc_setAssociatedObject(dynamicClass, kEMASCurlConfigurationKey, [configuration copy], OBJC_ASSOCIATION_RETAIN);

    // 创建包装器来管理动态类的生命周期
    EMASCurlSessionConfigurationWrapper *wrapper = [[EMASCurlSessionConfigurationWrapper alloc]
                                                     initWithDynamicClass:dynamicClass];
    objc_setAssociatedObject(sessionConfiguration, kEMASCurlWrapperKey, wrapper, OBJC_ASSOCIATION_RETAIN);

    NSMutableArray *protocolsArray = [NSMutableArray arrayWithArray:sessionConfiguration.protocolClasses];
    [protocolsArray insertObject:dynamicClass atIndex:0];
    [sessionConfiguration setProtocolClasses:protocolsArray];
}

#pragma mark - Legacy API (Backward Compatibility)

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
    [self ensureGlobalConfiguration];
    s_globalConfiguration.httpVersion = version;
}

+ (void)setBuiltInGzipEnabled:(BOOL)enabled {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.builtInGzipEnabled = enabled;
}

+ (void)setSelfSignedCAFilePath:(nonnull NSString *)selfSignedCAFilePath {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.selfSignedCAFilePath = selfSignedCAFilePath;
}

+ (void)setBuiltInRedirectionEnabled:(BOOL)enabled {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.builtInRedirectionEnabled = enabled;
}

+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled {
    [EMASCurlLogger setLogLevel:EMASCurlLogLevelDebug];
}

+ (void)setDNSResolver:(nonnull Class<EMASCurlProtocolDNSResolver>)dnsResolver {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.dnsResolverClass = dnsResolver;
}

+ (void)setUploadProgressUpdateBlockForRequest:(nonnull NSMutableURLRequest *)request uploadProgressUpdateBlock:(nonnull EMASCurlUploadProgressUpdateBlock)uploadProgressUpdateBlock {
    [NSURLProtocol setProperty:[uploadProgressUpdateBlock copy] forKey:kEMASCurlUploadProgressUpdateBlockKey inRequest:request];
}

+ (void)setMetricsObserverBlockForRequest:(nonnull NSMutableURLRequest *)request metricsObserverBlock:(nonnull EMASCurlMetricsObserverBlock)metricsObserverBlock {
    [NSURLProtocol setProperty:[metricsObserverBlock copy] forKey:kEMASCurlMetricsObserverBlockKey inRequest:request];
}

+ (void)setConnectTimeoutIntervalForRequest:(nonnull NSMutableURLRequest *)request connectTimeoutInterval:(NSTimeInterval)timeoutInterval {
    [NSURLProtocol setProperty:@(timeoutInterval) forKey:kEMASCurlConnectTimeoutIntervalKey inRequest:request];
}

+ (void)setHijackDomainWhiteList:(nullable NSArray<NSString *> *)domainWhiteList {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.hijackDomainWhiteList = domainWhiteList;
}

+ (void)setHijackDomainBlackList:(nullable NSArray<NSString *> *)domainBlackList {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.hijackDomainBlackList = domainBlackList;
}

+ (void)setPublicKeyPinningKeyPath:(nullable NSString *)publicKeyPath {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.publicKeyPinningKeyPath = publicKeyPath;
}

+ (void)setCertificateValidationEnabled:(BOOL)enabled {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.certificateValidationEnabled = enabled;
}

+ (void)setDomainNameVerificationEnabled:(BOOL)enabled {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.domainNameVerificationEnabled = enabled;
}

+ (void)setManualProxyServer:(nullable NSString *)proxyServerURL {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.manualProxyServer = proxyServerURL;

    __block BOOL shouldInvalidateTimer = NO;
    __block BOOL shouldStartTimer = NO;

    dispatch_sync(s_serialQueue, ^{
        if (proxyServerURL && proxyServerURL.length > 0) {
            s_manualProxyEnabled = YES;
            s_proxyServer = [proxyServerURL copy];
            shouldInvalidateTimer = YES;
        } else {
            s_manualProxyEnabled = NO;
            s_proxyServer = nil;
            shouldStartTimer = YES;
        }
    });

    dispatch_async(dispatch_get_main_queue(), ^{
        if (shouldInvalidateTimer && s_proxyUpdateTimer) {
            [s_proxyUpdateTimer invalidate];
            s_proxyUpdateTimer = nil;
            EMAS_LOG_INFO(@"EC-Proxy", @"Manual proxy enabled: %@", proxyServerURL);
        } else if (shouldStartTimer && !s_proxyUpdateTimer) {
            [self startProxyUpdatingTimer];
            EMAS_LOG_INFO(@"EC-Proxy", @"Manual proxy disabled, reverting to system settings");
        }
    });
}

#pragma mark - 日志相关方法

+ (void)setCacheEnabled:(BOOL)enabled {
    [self ensureGlobalConfiguration];
    s_globalConfiguration.cacheEnabled = enabled;
}

+ (void)setLogLevel:(EMASCurlLogLevel)logLevel {
    [EMASCurlLogger setLogLevel:logLevel];
}

+ (EMASCurlLogLevel)currentLogLevel {
    return [EMASCurlLogger currentLogLevel];
}

#pragma mark - Configuration Helper Methods

+ (void)ensureGlobalConfiguration {
    if (!s_globalConfiguration) {
        s_globalConfiguration = [EMASCurlConfiguration defaultConfiguration];
    }
}

+ (EMASCurlConfiguration *)globalConfiguration {
    [self ensureGlobalConfiguration];
    return s_globalConfiguration;
}

+ (EMASCurlConfiguration *)configurationForCurrentClass {
    // 直接从动态类获取关联的配置
    EMASCurlConfiguration *config = objc_getAssociatedObject(self, kEMASCurlConfigurationKey);
    if (config) {
        return config;
    }

    // 兼容性回退：如果没有特定的配置，则使用全局配置
    return [self globalConfiguration];
}

#pragma mark * NSURLProtocol overrides

- (instancetype)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id<NSURLProtocolClient>)client {
    self = [super initWithRequest:request cachedResponse:cachedResponse client:client];
    if (self) {
        _shouldCancel = NO;
        _cleanupSemaphore = dispatch_semaphore_create(0);
        _totalBytesSent = 0;
        _totalBytesExpected = 0;
        _currentResponse = [CurlHTTPResponse new];
        _resolveDomainTimeInterval = -1;
        _receivedResponseData = [NSMutableData new];

        _uploadProgressUpdateBlock = [NSURLProtocol propertyForKey:kEMASCurlUploadProgressUpdateBlockKey inRequest:request];
        _metricsObserverBlock = [NSURLProtocol propertyForKey:kEMASCurlMetricsObserverBlockKey inRequest:request];

        _configuration = [[self class] configurationForCurrentClass];
    }
    return self;
}

// 在类加载方法中初始化libcurl
+ (void)load {
    curl_global_init(CURL_GLOBAL_DEFAULT);

    // 读取runtime libcurl对于http2/3的支持
    curl_version_info_data *version_info = curl_version_info(CURLVERSION_NOW);
    curlFeatureHttp2 = (version_info->features & CURL_VERSION_HTTP2) ? YES : NO;
    curlFeatureHttp3 = (version_info->features & CURL_VERSION_HTTP3) ? YES : NO;

    // 初始化基础设施组件
    s_responseCache = [EMASCurlResponseCache new];
    s_proxyServer = nil;
    s_manualProxyEnabled = NO;

    // 初始化全局配置为默认值
    s_globalConfiguration = [EMASCurlConfiguration defaultConfiguration];
    // 调整默认值以保持向后兼容
    s_globalConfiguration.httpVersion = HTTP1; // 为了向后兼容，保持HTTP1作为默认

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_serialQueue = dispatch_queue_create("com.alicloud.emascurl.serialQueue", DISPATCH_QUEUE_SERIAL);
        s_cacheQueue = dispatch_queue_create("com.alicloud.emascurl.cacheQueue", DISPATCH_QUEUE_SERIAL);
    });

    // 设置定时任务读取proxy
    [self startProxyUpdatingTimer];
}

+ (void)startProxyUpdatingTimer {
    // 确保在主线程上操作定时器
    dispatch_async(dispatch_get_main_queue(), ^{
        // 如果定时器已存在，先停止旧的
        if (s_proxyUpdateTimer) {
            [s_proxyUpdateTimer invalidate];
            s_proxyUpdateTimer = nil;
        }
        // 设置一个定时器，10s更新一次proxy设置
        NSTimer *timer = [NSTimer timerWithTimeInterval:10.0
                                                 target:self
                                               selector:@selector(updateProxySettings)
                                               userInfo:nil
                                                repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        s_proxyUpdateTimer = timer; // 保存定时器实例
        [self updateProxySettings]; // 立即执行一次更新
    });
}

+ (void)updateProxySettings {
    dispatch_sync(s_serialQueue, ^{
        // If manual proxy is enabled, don't update anything
        if (s_manualProxyEnabled) {
            return;
        }

        // Get and process system proxy within the locked section
        CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
        if (!proxySettings) {
            s_proxyServer = nil;
            return;
        }

        NSDictionary *proxyDict = (__bridge NSDictionary *)(proxySettings);
        if (!(proxyDict[(NSString *)kCFNetworkProxiesHTTPEnable])) {
            s_proxyServer = nil;
            CFRelease(proxySettings);
            return;
        }

        NSString *httpProxy = proxyDict[(NSString *)kCFNetworkProxiesHTTPProxy];
        NSNumber *httpPort = proxyDict[(NSString *)kCFNetworkProxiesHTTPPort];

        if (httpProxy && httpPort) {
            s_proxyServer = [NSString stringWithFormat:@"http://%@:%@", httpProxy, httpPort];
        } else {
            s_proxyServer = nil;
        }

        CFRelease(proxySettings);
    });
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
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

    EMASCurlConfiguration *config = [self configurationForCurrentClass];

    // 检查请求的host是否在白名单或黑名单中
    NSString *host = request.URL.host;
    if (!host) {
        EMAS_LOG_DEBUG(@"EC-Request", @"Rejected request without host");
        return NO;
    }

    if (config.hijackDomainBlackList && config.hijackDomainBlackList.count > 0) {
        for (NSString *blacklistDomain in config.hijackDomainBlackList) {
            if ([host hasSuffix:blacklistDomain]) {
                EMAS_LOG_DEBUG(@"EC-Request", @"Request rejected by domain blacklist: %@", host);
                return NO;
            }
        }
    }
    if (config.hijackDomainWhiteList && config.hijackDomainWhiteList.count > 0) {
        for (NSString *whitelistDomain in config.hijackDomainWhiteList) {
            if ([host hasSuffix:whitelistDomain]) {
                EMAS_LOG_DEBUG(@"EC-Request", @"Request filtered by domain whitelist: %@", host);
                return YES;
            }
        }
        EMAS_LOG_DEBUG(@"EC-Request", @"Request rejected: not in domain whitelist: %@", host);
        return NO;
    }

    NSString *userAgent = [request valueForHTTPHeaderField:@"User-Agent"];
    if (userAgent && [userAgent containsString:@"HttpdnsSDK"]) {
        // 不拦截来自Httpdns SDK的请求
        EMAS_LOG_DEBUG(@"EC-Request", @"Rejected HttpdnsSDK request");
        return NO;
    }

    EMAS_LOG_DEBUG(@"EC-Request", @"Request accepted for processing: %@", request.URL.absoluteString);
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kEMASCurlHandledKey inRequest:mutableRequest];
    return mutableRequest;
}

- (void)startLoading {
    EMAS_LOG_INFO(@"EC-Protocol", @"Starting request for URL: %@", self.request.URL.absoluteString);

    // 检查是否启用缓存以及是否是可缓存的请求
    __block BOOL useCache = NO;

    dispatch_sync(s_cacheQueue, ^{
        if (!self.configuration.cacheEnabled) {
            return;
        }

        if (![[self.request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {
            return;
        }

        // 从我们的缓存逻辑获取响应
        NSCachedURLResponse *cachedResponse = [s_responseCache cachedResponseForRequest:self.request];

        if (cachedResponse) {
            BOOL isFresh = [cachedResponse emas_isResponseStillFreshForRequest:self.request];
            BOOL requiresRevalidation = [cachedResponse emas_requiresRevalidation];

            if (isFresh && !requiresRevalidation) {
                // 响应是新鲜的，且不需要因为 no-cache 等指令而重新验证
                useCache = YES; // 标记已使用缓存
                EMAS_LOG_INFO(@"EC-Cache", @"Cache hit for request: %@", self.request.URL.absoluteString);
                [self.client URLProtocol:self didReceiveResponse:cachedResponse.response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                [self.client URLProtocol:self didLoadData:cachedResponse.data];
                [self.client URLProtocolDidFinishLoading:self];
                // 注意：因为在dispatch_sync块中，直接return可能不是预期行为，
                // 取决于外部如何处理 useCache 标记。这里假设 useCache 会被外部检查。
            } else {
                // 响应是陈旧的，或者新鲜但需要重新验证 (no-cache)。
                // 条件请求头将在后续步骤中添加 (如果 cachedResponse 有 ETag/Last-Modified)。
                // cachedResponseForRequest 保证了如果到这里 cachedResponse 非nil，它至少有验证器。
                EMAS_LOG_DEBUG(@"EC-Cache", @"Cache validation: fresh=%d, requires_revalidation=%d", isFresh, requiresRevalidation);
            }
        }
    });

    // 如果使用了缓存，则直接返回
    if (useCache) {
        dispatch_semaphore_signal(self.cleanupSemaphore);
        return;
    }

    // 原始的网络请求处理逻辑
    CURL *easyHandle = curl_easy_init();
    self.easyHandle = easyHandle;
    if (!easyHandle) {
        NSError *error = [NSError errorWithDomain:@"fail to init easy handle." code:-1 userInfo:nil];
        EMAS_LOG_ERROR(@"EC-Protocol", @"Failed to create easy handle for URL: %@", self.request.URL.absoluteString);
        [self reportNetworkMetric:NO error:error];
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    EMAS_LOG_DEBUG(@"EC-Protocol", @"Easy handle created successfully for URL: %@", self.request.URL.absoluteString);

    [self populateRequestHeader:easyHandle];
    [self populateRequestBody:easyHandle];

    NSError *error = nil;
    [self configEasyHandle:easyHandle error:&error];
    if (error) {
        EMAS_LOG_ERROR(@"EC-Protocol", @"Failed to configure easy handle: %@", error.localizedDescription);
        [self reportNetworkMetric:NO error:error];
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    [[EMASCurlManager sharedInstance] enqueueNewEasyHandle:easyHandle completion:^(BOOL succeed, NSError *error) {
        [self reportNetworkMetric:succeed error:error];

        // 如果请求成功且状态码为200，则尝试缓存响应
        if (succeed &&
            self.currentResponse.statusCode == 200 &&
            self.configuration.cacheEnabled &&
            [[self.request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {

            dispatch_sync(s_cacheQueue, ^{
                NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                                              statusCode:self.currentResponse.statusCode
                                                                             HTTPVersion:self.currentResponse.httpVersion
                                                                            headerFields:self.currentResponse.headers];
                if (httpResponse) {
                    EMAS_LOG_INFO(@"EC-Cache", @"Response cached for URL: %@", self.request.URL.absoluteString);
                    [s_responseCache cacheResponse:httpResponse
                                              data:self.receivedResponseData
                                        forRequest:self.request
                                   withHTTPVersion:@"HTTP/2"];
                }
            });
        }

        if (succeed) {
            EMAS_LOG_DEBUG(@"EC-Protocol", @"Request processing completed with status: %ld", (long)self.currentResponse.statusCode);
            [self.client URLProtocolDidFinishLoading:self];
        } else {
            EMAS_LOG_ERROR(@"EC-Protocol", @"Request failed: %@", error ? error.localizedDescription : @"Unknown error");
            [self.client URLProtocol:self didFailWithError:error];
        }

        dispatch_semaphore_signal(self.cleanupSemaphore);
    }];
}

- (void)stopLoading {
    self.shouldCancel = YES;
    dispatch_semaphore_wait(self.cleanupSemaphore, DISPATCH_TIME_FOREVER);

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
    if (self.easyHandle) {
        curl_easy_cleanup(self.easyHandle);
        self.easyHandle = nil;
    }
}

- (void)reportNetworkMetric:(BOOL)success error:(NSError *)error {
    if (!self.metricsObserverBlock || !self.easyHandle) {
        return;
    }

    double nameLookupTime = 0;
    double connectTime = 0;
    double appConnectTime = 0;
    double preTransferTime = 0;
    double startTransferTime = 0;
    double totalTime = 0;

    if (self.resolveDomainTimeInterval > 0) {
        nameLookupTime = self.resolveDomainTimeInterval;
    } else {
        curl_easy_getinfo(self.easyHandle, CURLINFO_NAMELOOKUP_TIME, &nameLookupTime);
    }
    curl_easy_getinfo(self.easyHandle, CURLINFO_CONNECT_TIME, &connectTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_APPCONNECT_TIME, &appConnectTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_PRETRANSFER_TIME, &preTransferTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_STARTTRANSFER_TIME, &startTransferTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_TOTAL_TIME, &totalTime);

    // 记录性能指标
    EMAS_LOG_INFO(@"EC-Performance", @"Request completed in %.0fms (DNS: %.0fms, Connect: %.0fms, Transfer: %.0fms)",
                  totalTime * 1000, nameLookupTime * 1000, connectTime * 1000, startTransferTime * 1000);

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
    switch (self.configuration.httpVersion) {
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
                curl_easy_setopt(easyHandle, CURLOPT_PIPEWAIT, 1L);
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
    } else if (self.configuration.builtInGzipEnabled) {
        // 用户没有手动设置Accept-Encoding头部，使用内置gzip设置
        curl_easy_setopt(easyHandle, CURLOPT_ACCEPT_ENCODING, "");
        EMAS_LOG_DEBUG(@"EC-Headers", @"Using built-in gzip encoding");
    }

    // 只对GET请求添加缓存相关条件头
    if (self.configuration.cacheEnabled && [[self.request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {
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

    self.inputStream = request.HTTPBodyStream;

    // 用read_cb回调函数来读取需要传输的数据
    curl_easy_setopt(easyHandle, CURLOPT_READFUNCTION, read_cb);
    // self传给read_cb函数的void *userp参数
    curl_easy_setopt(easyHandle, CURLOPT_READDATA, (__bridge void *)self);

    NSString *contentLength = [request valueForHTTPHeaderField:@"Content-Length"];
    if (!contentLength) {
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
    curl_easy_setopt(easyHandle, CURLOPT_POSTFIELDSIZE, length);
}

- (void)configEasyHandle:(CURL *)easyHandle error:(NSError **)error {
    // 假如是quic这个framework，由于使用的boringssl无法访问苹果native CA，需要从Bundle中读取CA
    if (curlFeatureHttp3) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSURL *bundleURL = [mainBundle URLForResource:@"EMASCAResource" withExtension:@"bundle"];
        if (!bundleURL) {
            *error = [NSError errorWithDomain:@"fail to load CA certificate." code:-3 userInfo:nil];
            return;
        }
        NSBundle *resourceBundle = [NSBundle bundleWithURL:bundleURL];
        NSString *filePath = [resourceBundle pathForResource:@"cacert" ofType:@"pem"];
        curl_easy_setopt(easyHandle, CURLOPT_CAINFO, [filePath UTF8String]);
    }

    // 是否设置自定义根证书
    if (self.configuration.selfSignedCAFilePath) {
        curl_easy_setopt(easyHandle, CURLOPT_CAINFO, [self.configuration.selfSignedCAFilePath UTF8String]);
    }

    // 配置证书校验
    if (self.configuration.certificateValidationEnabled) {
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYPEER, 1L);
    } else {
        EMAS_LOG_INFO(@"EC-SSL", @"Certificate validation disabled");
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYPEER, 0L);
    }

    // 配置域名校验
    // 0: 不校验域名
    // 1: 校验域名是否存在于证书中，但仅用于提示 (libcurl < 7.28.0)
    // 2: 校验域名是否存在于证书中且匹配 (libcurl >= 7.28.0 推荐)
    if (self.configuration.domainNameVerificationEnabled) {
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYHOST, 2L);
    } else {
        EMAS_LOG_INFO(@"EC-SSL", @"Domain name verification disabled");
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYHOST, 0L);
    }

    // 设置公钥固定
    if (self.configuration.publicKeyPinningKeyPath) {
        EMAS_LOG_INFO(@"EC-SSL", @"Using public key pinning for host: %@", self.request.URL.host);
        curl_easy_setopt(easyHandle, CURLOPT_PINNEDPUBLICKEY, [self.configuration.publicKeyPinningKeyPath UTF8String]);
    }

    // 假如设置了自定义resolve，则使用
    if (self.configuration.dnsResolverClass) {
        NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
        if ([self preResolveDomain:easyHandle]) {
            self.resolveDomainTimeInterval = [[NSDate date] timeIntervalSince1970] - startTime;
        }
    }

    // 设置cookie
    EMASCurlCookieStorage *cookieStorage = [EMASCurlCookieStorage sharedStorage];
    NSString *cookieString = [cookieStorage cookieStringForURL:self.request.URL];
    if (cookieString) {
        curl_easy_setopt(easyHandle, CURLOPT_COOKIE, [cookieString UTF8String]);
    }

    dispatch_sync(s_serialQueue, ^{
        // 设置proxy
        if (s_proxyServer) {
            curl_easy_setopt(easyHandle, CURLOPT_PROXY, [s_proxyServer UTF8String]);
        }
    });

    // 设置debug回调函数以输出日志
    if (EMASCurlLogger.currentLogLevel >= EMASCurlLogLevelDebug) {
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
    if (connectTimeoutInterval) {
        curl_easy_setopt(easyHandle, CURLOPT_CONNECTTIMEOUT, connectTimeoutInterval.longValue);
    }

    // 设置请求超时时间
    NSTimeInterval requestTimeoutInterval = self.request.timeoutInterval;
    if (requestTimeoutInterval) {
        curl_easy_setopt(easyHandle, CURLOPT_TIMEOUT, requestTimeoutInterval);
    }

    // 开启重定向
    if (self.configuration.builtInRedirectionEnabled) {
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
    NSString *address = [self.configuration.dnsResolverClass resolveDomain:host];
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
        if (statusCode == 304 && protocol.configuration.cacheEnabled) {
            // 查找缓存
            NSCachedURLResponse *cachedResponse = [s_responseCache cachedResponseForRequest:protocol.request];
            if (cachedResponse) {
                // 使用缓存的响应数据，但更新头部
                NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:protocol.request.URL
                                                                              statusCode:protocol.currentResponse.statusCode
                                                                             HTTPVersion:protocol.currentResponse.httpVersion
                                                                            headerFields:protocol.currentResponse.headers];
                NSCachedURLResponse *updatedResponse = [s_responseCache updateCachedResponseWithHeaders:httpResponse.allHeaderFields
                                                                                             forRequest:protocol.request];
                if (updatedResponse) {
                    [protocol.client URLProtocol:protocol didReceiveResponse:updatedResponse.response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                    [protocol.client URLProtocol:protocol didLoadData:updatedResponse.data];
                    return totalSize;
                }
            }
        }

        NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:protocol.request.URL
                                                                      statusCode:protocol.currentResponse.statusCode
                                                                     HTTPVersion:protocol.currentResponse.httpVersion
                                                                    headerFields:protocol.currentResponse.headers];
        if (isRedirectionStatusCode(statusCode)) {
            if (!protocol.configuration.builtInRedirectionEnabled) {
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
                    [protocol.client URLProtocol:protocol wasRedirectedToRequest:redirectedRequest redirectResponse:httpResponse];
                }
            }
            [protocol.currentResponse reset];
        } else if (isInformationalStatusCode(statusCode)) {
            [protocol.currentResponse reset];
        } else if (isConnectEstablishedStatusCode(statusCode, reasonPhrase)) {
            [protocol.currentResponse reset];
        } else {
            [protocol.client URLProtocol:protocol didReceiveResponse:httpResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            protocol.currentResponse.isFinalResponse = YES;
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

    // 收集响应数据用于缓存
    if (protocol.configuration.cacheEnabled && protocol.currentResponse.statusCode == 200 &&
        [[protocol.request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {
        [protocol.receivedResponseData appendData:data];
    }

    // 只有确认获得已经读取了最后一个响应，接受的数据才视为有效数据
    if (protocol.currentResponse.isFinalResponse) {
        [protocol.client URLProtocol:protocol didLoadData:data];
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

#pragma mark - Dynamic Class Management

+ (void)cleanupDynamicClass:(Class)dynamicClass {
    if (!dynamicClass || ![dynamicClass isSubclassOfClass:[EMASCurlProtocol class]]) {
        return;
    }

    // 清理直接关联到动态类的配置对象
    objc_setAssociatedObject(dynamicClass, kEMASCurlConfigurationKey, nil, OBJC_ASSOCIATION_RETAIN);

    // 注销类（注意：在实际使用中要谨慎，确保没有实例在使用）
    // objc_disposeClassPair(dynamicClass); // 暂时注释掉
}

@end
