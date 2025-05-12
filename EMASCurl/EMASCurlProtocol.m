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
#import <curl/curl.h>

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
static NSString * _Nonnull const kEMASCurlForceRefreshKey = @"kEMASCurlForceRefreshKey";

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

@property (nonatomic, strong) NSMutableData *receivedResponseData;

@end

static HTTPVersion s_httpVersion;

// runtime 的libcurl xcframework是否支持HTTP2
static bool curlFeatureHttp2;

// runtime 的libcurl xcframework是否支持HTTP3
static bool curlFeatureHttp3;

static bool s_enableBuiltInGzip;

static NSString *s_caFilePath;

static BOOL s_enableBuiltInRedirection;

static NSString *s_proxyServer;
static dispatch_queue_t s_serialQueue;

static Class<EMASCurlProtocolDNSResolver> s_dnsResolverClass;

static bool s_enableDebugLog;

// 标记是否启用了手动代理
static BOOL s_manualProxyEnabled;
// 定时更新系统代理设置的定时器
static NSTimer *s_proxyUpdateTimer;

// 拦截域名白名单
static NSArray<NSString *> *s_domainWhiteList;
static NSArray<NSString *> *s_domainBlackList;

// 公钥固定(Public Key Pinning)的公钥文件路径
static NSString *s_publicKeyPinningKeyPath;

static EMASCurlResponseCache *s_responseCache;
static BOOL s_cacheEnabled;
static dispatch_queue_t s_cacheQueue;

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
    s_httpVersion = version;
}

+ (void)setBuiltInGzipEnabled:(BOOL)enabled {
    s_enableBuiltInGzip = enabled;
}

+ (void)setSelfSignedCAFilePath:(nonnull NSString *)selfSignedCAFilePath {
    s_caFilePath = selfSignedCAFilePath;
}

+ (void)setBuiltInRedirectionEnabled:(BOOL)enabled {
    s_enableBuiltInRedirection = enabled;
}

+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled {
    s_enableDebugLog = debugLogEnabled;
}

+ (void)setDNSResolver:(nonnull Class<EMASCurlProtocolDNSResolver>)dnsResolver {
    s_dnsResolverClass = dnsResolver;
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
    s_domainWhiteList = domainWhiteList;
}

+ (void)setHijackDomainBlackList:(nullable NSArray<NSString *> *)domainBlackList {
    s_domainBlackList = domainBlackList;
}

+ (void)setPublicKeyPinningKeyPath:(nullable NSString *)publicKeyPath {
    s_publicKeyPinningKeyPath = [publicKeyPath copy];
}

+ (void)setManualProxyServer:(nullable NSString *)proxyServerURL {
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
            NSLog(@"[EMASCurlProtocol] Manual proxy enabled: %@", proxyServerURL);
        } else if (shouldStartTimer && !s_proxyUpdateTimer) {
            [self startProxyUpdatingTimer];
            NSLog(@"[EMASCurlProtocol] Manual proxy disabled, reverting to system settings.");
        }
    });
}

+ (void)setCacheEnabled:(BOOL)enabled {
    dispatch_sync(s_cacheQueue, ^{
        s_cacheEnabled = enabled;
    });
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

    s_httpVersion = HTTP1;
    s_enableDebugLog = NO;

    s_enableBuiltInGzip = YES;
    s_enableBuiltInRedirection = YES;

    s_responseCache = [EMASCurlResponseCache new];

    s_proxyServer = nil;
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
        return NO;
    }

    // 不拦截已经处理过的请求
    if ([NSURLProtocol propertyForKey:kEMASCurlHandledKey inRequest:request]) {
        return NO;
    }

    // 不是http或https，则不拦截
    if (!([request.URL.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
         [request.URL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)) {
        return NO;
    }

    // 检查请求的host是否在白名单或黑名单中
    NSString *host = request.URL.host;
    if (!host) {
        return NO;
    }
    if (s_domainBlackList && s_domainBlackList.count > 0) {
        for (NSString *blacklistDomain in s_domainBlackList) {
            if ([host hasSuffix:blacklistDomain]) {
                return NO;
            }
        }
    }
    if (s_domainWhiteList && s_domainWhiteList.count > 0) {
        for (NSString *whitelistDomain in s_domainWhiteList) {
            if ([host hasSuffix:whitelistDomain]) {
                return YES;
            }
        }
        return NO;
    }

    NSString *userAgent = [request valueForHTTPHeaderField:@"User-Agent"];
    if (userAgent && [userAgent containsString:@"HttpdnsSDK"]) {
        // 不拦截来自Httpdns SDK的请求
        return NO;
    }

    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kEMASCurlHandledKey inRequest:mutableRequest];
    return mutableRequest;
}

- (void)startLoading {
    // 检查是否启用缓存以及是否是可缓存的请求
    __block BOOL useCache = NO;
    __block BOOL forceRefresh = NO;

    dispatch_sync(s_cacheQueue, ^{
        if (!s_cacheEnabled) {
            return;
        }

        // 只有GET方法才使用缓存
        if (![[self.request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {
            return;
        }

        // 检查是否强制刷新
        forceRefresh = [NSURLProtocol propertyForKey:kEMASCurlForceRefreshKey inRequest:self.request] != nil;
        if (forceRefresh) {
            return;
        }

        // 尝试从缓存获取
        NSCachedURLResponse *cachedResponse = [s_responseCache getCachedResponseWithRequest:self.request];
        if (cachedResponse && ![cachedResponse emas_isExpired]) {
            useCache = YES;

            // 使用缓存的响应
            [self.client URLProtocol:self didReceiveResponse:cachedResponse.response cacheStoragePolicy:NSURLCacheStorageAllowed];
            [self.client URLProtocol:self didLoadData:cachedResponse.data];
            [self.client URLProtocolDidFinishLoading:self];
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
        [self reportNetworkMetric:NO error:error];
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    [self populateRequestHeader:easyHandle];
    [self populateRequestBody:easyHandle];

    NSError *error = nil;
    [self configEasyHandle:easyHandle error:&error];
    if (error) {
        [self reportNetworkMetric:NO error:error];
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    [[EMASCurlManager sharedInstance] enqueueNewEasyHandle:easyHandle completion:^(BOOL succeed, NSError *error) {
        [self reportNetworkMetric:succeed error:error];

        // 如果请求成功且状态码为200，则尝试缓存响应
        if (succeed &&
            self.currentResponse.statusCode == 200 &&
            s_cacheEnabled &&
            [[self.request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {

            dispatch_sync(s_cacheQueue, ^{
                NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                                              statusCode:self.currentResponse.statusCode
                                                                             HTTPVersion:self.currentResponse.httpVersion
                                                                            headerFields:self.currentResponse.headers];
                if (httpResponse) {
                    [s_responseCache cacheWithHTTPURLResponse:httpResponse
                                                        data:self.receivedResponseData
                                                     request:self.request];
                }
            });
        }

        if (succeed) {
            [self.client URLProtocolDidFinishLoading:self];
        } else {
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
    switch (s_httpVersion) {
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

    if (s_enableBuiltInGzip) {
        // 配置支持的HTTP压缩算法，""代表自动检测内置的算法，目前zlib支持deflate与gzip
        curl_easy_setopt(easyHandle, CURLOPT_ACCEPT_ENCODING, "");
    }

    // 将拦截到的request的header字段进行透传
    self.requestHeaderFields = [self convertHeadersToCurlSlist:request.allHTTPHeaderFields];

    // 只对GET请求添加缓存相关条件头
    if (s_cacheEnabled && [[request.HTTPMethod uppercaseString] isEqualToString:@"GET"]) {
        // 检查是否存在已过期的缓存，如果有则添加条件头
        NSCachedURLResponse *cachedResponse = [s_responseCache getCachedResponseWithRequest:request];
        if (cachedResponse && [cachedResponse emas_isExpired]) {
            NSString *etag = [cachedResponse emas_etag];
            if (etag) {
                NSString *ifNoneMatchHeader = [NSString stringWithFormat:@"If-None-Match: %@", etag];
                self.requestHeaderFields = curl_slist_append(self.requestHeaderFields, [ifNoneMatchHeader UTF8String]);
            }

            NSString *lastModified = [cachedResponse emas_lastModified];
            if (lastModified) {
                NSString *ifModifiedSinceHeader = [NSString stringWithFormat:@"If-Modified-Since: %@", lastModified];
                self.requestHeaderFields = curl_slist_append(self.requestHeaderFields, [ifModifiedSinceHeader UTF8String]);
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
    if (s_caFilePath) {
        curl_easy_setopt(easyHandle, CURLOPT_CAINFO, [s_caFilePath UTF8String]);
    }

    // 假如设置了自定义resolve，则使用
    if (s_dnsResolverClass) {
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
    if (s_enableDebugLog) {
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
    if (s_enableBuiltInRedirection) {
        curl_easy_setopt(easyHandle, CURLOPT_FOLLOWLOCATION, 1L);
    } else {
        curl_easy_setopt(easyHandle, CURLOPT_FOLLOWLOCATION, 0L);
    }

    // 为了线程安全，设置NOSIGNAL
    curl_easy_setopt(easyHandle, CURLOPT_NOSIGNAL, 1L);

    // 设置公钥固定
    if (s_publicKeyPinningKeyPath) {
        curl_easy_setopt(easyHandle, CURLOPT_PINNEDPUBLICKEY, [s_publicKeyPinningKeyPath UTF8String]);
    }
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

    NSString *address = [s_dnsResolverClass resolveDomain:host];
    if (!address) {
        return NO;
    }

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

// 将拦截到的request中的header字段，转换为一个curl list
- (struct curl_slist *)convertHeadersToCurlSlist:(NSDictionary<NSString *, NSString *> *)headers {
    struct curl_slist *headerFields = NULL;
    BOOL userAgentPresent = NO; // 标记User-Agent是否存在

    for (NSString *key in headers) {
        // 对于Content-Length，使用CURLOPT_POSTFIELDSIZE_LARGE指定，不要在这里透传，否则POST重定向为GET时仍会保留Content-Length，导致错误
        if ([key caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame) {
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
    } else {
        NSRange delimiterRange = [headerLine rangeOfString:@": "];
        if (delimiterRange.location != NSNotFound) {
            NSString *key = [headerLine substringToIndex:delimiterRange.location];
            NSString *value = [headerLine substringFromIndex:delimiterRange.location + delimiterRange.length];

            // 设置cookie
            if ([key caseInsensitiveCompare:@"set-cookie"] == NSOrderedSame) {
                EMASCurlCookieStorage *cookieStorage = [EMASCurlCookieStorage sharedStorage];
                [cookieStorage setCookieWithString:value forURL:protocol.request.URL];
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
        if (statusCode == 304 && s_cacheEnabled) {
            // 查找缓存
            NSCachedURLResponse *cachedResponse = [s_responseCache getCachedResponseWithRequest:protocol.request];
            if (cachedResponse) {
                // 使用缓存的响应数据，但更新头部
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)protocol.currentResponse;
                NSCachedURLResponse *updatedResponse = [s_responseCache updateCachedResponseWithURLResponse:httpResponse
                                                                                                    request:protocol.request];
                if (updatedResponse) {
                    [protocol.client URLProtocol:protocol didReceiveResponse:updatedResponse.response
                                                      cacheStoragePolicy:NSURLCacheStorageAllowed];
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
            if (!s_enableBuiltInRedirection) {
                // 关闭了重定向支持，则把重定向信息往外传递
                __block NSString *location = nil;
                [protocol.currentResponse.headers enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
                    if ([key caseInsensitiveCompare:@"Location"] == NSOrderedSame) {
                        location = obj;
                        *stop = YES;
                    }
                }];
                if (location) {
                    NSURL *locationURL = [NSURL URLWithString:location relativeToURL:protocol.request.URL];
                    NSMutableURLRequest *redirectedRequest = [protocol.request mutableCopy];
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
            [protocol.client URLProtocol:protocol didReceiveResponse:httpResponse cacheStoragePolicy:NSURLCacheStorageAllowed];
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
    if (s_cacheEnabled && protocol.currentResponse.statusCode == 200 &&
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
    switch (type) {
        case CURLINFO_TEXT:
            NSLog(@"[CURLINFO_TEXT] %.*s", (int)size, data);
            break;
        case CURLINFO_HEADER_IN:
            NSLog(@"[CURLINFO_HEADER_IN] %.*s", (int)size, data);
            break;
        case CURLINFO_HEADER_OUT:
            NSLog(@"[CURLINFO_HEADER_OUT] %.*s", (int)size, data);
            break;
        case CURLINFO_DATA_IN:
            NSLog(@"[CURLINFO_DATA_IN] %.*s", (int)size, data);
            break;
        case CURLINFO_DATA_OUT:
            NSLog(@"[CURLINFO_DATA_OUT] %.*s", (int)size, data);
            break;
        case CURLINFO_SSL_DATA_IN:
            NSLog(@"[CURLINFO_SSL_DATA_IN] %.*s", (int)size, data);
            break;
        case CURLINFO_SSL_DATA_OUT:
            NSLog(@"[CURLINFO_SSL_DATA_OUT] %.*s", (int)size, data);
            break;
        case CURLINFO_END:
            NSLog(@"[CURLINFO_END] %.*s", (int)size, data);
        default:
            break;
    }
    return 0;
}

@end
