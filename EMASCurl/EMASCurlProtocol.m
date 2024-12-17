//
//  EMASCurlProtocol.m
//  EMASCurl
//
//  Created by xin yu on 2024/10/29.
//

#import "EMASCurlProtocol.h"
#import "EMASCurlManager.h"
#import <curl/curl.h>

@interface EMASCurlProtocol()

@property (nonatomic, assign) CURL *easyHandle;

@property (nonatomic, strong) NSInputStream *inputStream;

@property (nonatomic, strong) NSMutableData *responseHeaderBuffer;

@property (nonatomic, assign) int64_t totalBytesSent;

@property (nonatomic, assign) int64_t totalBytesExpected;

@property (nonatomic, assign) BOOL isFinalResponse;

@property (atomic, assign) BOOL shouldCancel;

@property (atomic, strong) dispatch_semaphore_t cleanupSemaphore;

@property (nonatomic, copy) EMASCurlUploadProgressUpdateBlock uploadProgressUpdateBlock;

@property (nonatomic, copy) EMASCurlMetricsObserverBlock metricsObserverBlock;

@end

static HTTPVersion s_httpVersion;

// runtime 的libcurl xcframework是否支持HTTP2
static bool curlFeatureHttp2;

// runtime 的libcurl xcframework是否支持HTTP3
static bool curlFeatureHttp3;

static NSString *s_caFilePath;

static NSString *s_proxyServer;

static Class<EMASCurlProtocolDNSResolver> s_dnsResolverClass;

static bool s_enableDebugLog;

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

+ (void)setSelfSignedCAFilePath:(nonnull NSString *)selfSignedCAFilePath {
    s_caFilePath = selfSignedCAFilePath;
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

#pragma mark * NSURLProtocol overrides

- (instancetype)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id<NSURLProtocolClient>)client {
    self = [super initWithRequest:request cachedResponse:cachedResponse client:client];
    if (self) {
        _shouldCancel = NO;
        _cleanupSemaphore = dispatch_semaphore_create(0);
        _responseHeaderBuffer = [[NSMutableData alloc] init];
        _isFinalResponse = YES;
        _totalBytesSent = 0;
        _totalBytesExpected = 0;

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

    // 设置定时任务读取proxy
    [self startProxyUpdatingTimer];
}

+ (void)startProxyUpdatingTimer {
    // 设置一个定时器，10s更新一次proxy设置
    NSTimer *timer = [NSTimer timerWithTimeInterval:10.0
                                             target:self
                                           selector:@selector(updateProxySettings)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    [self updateProxySettings];
}

+ (void)updateProxySettings {
    CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
    if (!proxySettings) {
        return;
    }
    NSDictionary *proxyDict = (__bridge NSDictionary *)(proxySettings);
    if (!(proxyDict[(NSString *)kCFNetworkProxiesHTTPEnable])) {
        CFRelease(proxySettings);
        return;
    }
    NSString *httpProxy = proxyDict[(NSString *)kCFNetworkProxiesHTTPProxy];
    NSNumber *httpPort = proxyDict[(NSString *)kCFNetworkProxiesHTTPPort];

    if (httpProxy && httpPort) {
        @synchronized (self) {
            s_proxyServer = [NSString stringWithFormat:@"http://%@:%@", httpProxy, httpPort];
        }
    }
    CFRelease(proxySettings);
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([[request.URL absoluteString] isEqual:@"about:blank"]) {
        return NO;
    }
    // 不是http或https，则不拦截
    if (!([request.URL.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
         [request.URL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)) {
        return NO;
    }
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    CURL *easyHandle = curl_easy_init();
    self.easyHandle = easyHandle;
    if (!easyHandle) {
        [self observeNetworkMetric];
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"fail to init easy handle" code:-1 userInfo:nil]];
        return;
    }

    [self populateRequestHeader:easyHandle];
    [self populateRequestBody:easyHandle];

    NSError *error = nil;
    [self configEasyHandle:easyHandle error:&error];
    if (error) {
        [self observeNetworkMetric];
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    [[EMASCurlManager sharedInstance] enqueueNewEasyHanlde:easyHandle completion:^(BOOL succeed, NSError *error) {
        [self observeNetworkMetric];

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
    if (self.easyHandle) {
        curl_easy_cleanup(self.easyHandle);
        self.easyHandle = nil;
    }
    self.responseHeaderBuffer = nil;
}

- (void)observeNetworkMetric {
    if (!self.metricsObserverBlock || !self.easyHandle) {
        return;
    }

    double nameLookupTime = 0;
    double connectTime = 0;
    double appConnectTime = 0;
    double preTransferTime = 0;
    double startTransferTime = 0;
    double totalTime = 0;

    curl_easy_getinfo(self.easyHandle, CURLINFO_NAMELOOKUP_TIME, &nameLookupTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_CONNECT_TIME, &connectTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_APPCONNECT_TIME, &appConnectTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_PRETRANSFER_TIME, &preTransferTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_STARTTRANSFER_TIME, &startTransferTime);
    curl_easy_getinfo(self.easyHandle, CURLINFO_TOTAL_TIME, &totalTime);

    self.metricsObserverBlock(self.request,
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
    if ([@"GET" isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_HTTPGET, 1);
    } else if ([@"POST" isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_POST, 1);
    } else if ([@"PUT" isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_UPLOAD, 1);
    } else if ([@"HEAD" isEqualToString:request.HTTPMethod]) {
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
            } else {
                curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
            }
            break;
        default:
            curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
            break;
    }

    // 配置支持的HTTP压缩算法，""代表自动检测内置的算法，目前zlib支持deflate与gzip
    curl_easy_setopt(easyHandle, CURLOPT_ACCEPT_ENCODING, "");

    // 将拦截到的request的header字段进行透传
    struct curl_slist *headerFields = [self convertHeadersToCurlSlist:request.allHTTPHeaderFields];
    curl_easy_setopt(easyHandle, CURLOPT_HTTPHEADER, headerFields);
}

- (void)populateRequestBody:(CURL *)easyHandle {
    NSURLRequest *request = self.request;

    self.inputStream = request.HTTPBodyStream;

    // 用read_cb回调函数来读取需要传输的数据
    curl_easy_setopt(easyHandle, CURLOPT_READFUNCTION, read_cb);
    // self传给read_cb函数的void *userp参数
    curl_easy_setopt(easyHandle, CURLOPT_READDATA, self);

    NSString *contentLength = [request valueForHTTPHeaderField:@"Content-Length"];
    if (contentLength) {
        int64_t length = [contentLength longLongValue];
        self.totalBytesExpected = length;
    } else {
        // If no Content-Length header, set expected bytes to -1
        self.totalBytesExpected = -1;
    }
}

- (void)configEasyHandle:(CURL *)easyHandle error:(NSError **)error {
    // 假如是quic这个framework，由于使用的boringssl无法访问苹果native CA，需要从Bundle中读取CA
    if (curlFeatureHttp3) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSURL *bundleURL = [mainBundle URLForResource:@"EMASCAResource" withExtension:@"bundle"];
        if (!bundleURL) {
            *error = [NSError errorWithDomain:@"fail to load CA certificate" code:-3 userInfo:nil];
            return;
        }
        NSBundle *resourceBundle = [NSBundle bundleWithURL:bundleURL];
        NSString *filePath = [resourceBundle pathForResource:@"cacert" ofType:@"pem"];
        curl_easy_setopt(easyHandle, CURLOPT_CAINFO, [filePath UTF8String]);
    }

    // 是否设置自定义根证书
    if (s_caFilePath) {
        curl_easy_setopt(easyHandle, CURLOPT_CAINFO, [s_caFilePath UTF8String]);
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYPEER, 1L);
        curl_easy_setopt(easyHandle, CURLOPT_SSL_VERIFYHOST, 2L);
    }

    // 假如设置了自定义resolve，则使用
    if (s_dnsResolverClass) {
        [self configCustomDNSResolver:easyHandle];
    }

    @synchronized ([EMASCurlProtocol class]) {
        // 设置proxy
        if (s_proxyServer) {
            curl_easy_setopt(easyHandle, CURLOPT_PROXY, [s_proxyServer UTF8String]);
        }
    }

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
    curl_easy_setopt(easyHandle, CURLOPT_FRESH_CONNECT, 0L);  // Allow connection reuse
    curl_easy_setopt(easyHandle, CURLOPT_FORBID_REUSE, 0L);   // Do not forbid reuse
    curl_easy_setopt(easyHandle, CURLOPT_TCP_KEEPIDLE, 60L);  // Start sending Keep-Alive probes after 60 seconds
    curl_easy_setopt(easyHandle, CURLOPT_TCP_KEEPINTVL, 60L); // Interval between Keep-Alive probes

    // 开启重定向
    curl_easy_setopt(easyHandle, CURLOPT_FOLLOWLOCATION, 1L);
    // 为了线程安全，设置NOSIGNAL
    curl_easy_setopt(easyHandle, CURLOPT_NOSIGNAL, 1L);
}

- (void)configCustomDNSResolver:(CURL *)easyHandle {
    NSURL *url = self.request.URL;
    if (!url || !url.host) {
        return;
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
            return;
        }
    }

    NSString *address = [s_dnsResolverClass resolveDomain:host];
    if (!address) {
        return;
    }

    // Format: +{host}:{port}:{ips}
    NSString *hostPortAddressString = [NSString stringWithFormat:@"+%@:%ld:%@",
                                     host,
                                     (long)resolvedPort,
                                     address];

    struct curl_slist *resolveList = NULL;
    resolveList = curl_slist_append(resolveList, [hostPortAddressString UTF8String]);
    if (resolveList) {
        curl_easy_setopt(easyHandle, CURLOPT_RESOLVE, resolveList);
    }
}

// 将拦截到的request中的header字段，转换为一个curl list
- (struct curl_slist *)convertHeadersToCurlSlist:(NSDictionary<NSString *, NSString *> *)headers {
    struct curl_slist *headerFields = NULL;
    for (NSString *key in headers) {
        // 对于Content-Length，使用CURLOPT_POSTFIELDSIZE_LARGE指定，不要在这里透传，否则POST重定向为GET时仍会保留Content-Length，导致错误
        if ([key isEqualToString:@"Content-Length"]) {
            continue;
        }
        NSString *value = headers[key];
        NSString *header = [NSString stringWithFormat:@"%@: %@", key, value];
        headerFields = curl_slist_append(headerFields, [header UTF8String]);
    }
    return headerFields;
}

#pragma mark * libcurl callback function

// libcurl的header回调函数，用于处理收到的header
static size_t header_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    EMASCurlProtocol *protocol = (__bridge EMASCurlProtocol *)userp;
    NSData *data = [NSData dataWithBytes:contents length:size * nmemb];

    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    // 检查是否是首部行
    if ([line hasPrefix:@"HTTP/"]) {
        // 检查是否是重定向、1开头的中间状态、代理的connect响应
        if ([line containsString:@" 3"] || [line containsString:@" 1"] || [line containsString:@"Connection established"]) {
            protocol.isFinalResponse = NO;
        } else {
            protocol.isFinalResponse = YES;
        }
    }

    // 如果是最后的Response则存储这个响应
    if (protocol.isFinalResponse) {
        [protocol.responseHeaderBuffer appendData:data];
    }

    // 检查是否是头部结束行
    if ([line isEqualToString:@"\r\n"]) {
        if (protocol.isFinalResponse) {
            NSURLResponse *response = convertHeaderToResponse(protocol.responseHeaderBuffer, protocol.request.URL);
            [protocol.client URLProtocol:protocol didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
        }
    }

    return size * nmemb;
}

// 将libcurl收到的header数据，转换为一个NSURLResponse
static NSURLResponse *convertHeaderToResponse(NSMutableData *receivedHeader, NSURL *url) {
    // 将 NSMutableData 转换为 NSString
    NSString *headerString = [[NSString alloc] initWithData:receivedHeader encoding:NSUTF8StringEncoding];

    // 以双换行分割成多个response
    NSArray<NSString *> *responses = [headerString componentsSeparatedByString:@"\r\n\r\n"];
    // 保留最后一个response，过滤掉separate出的空字符串
    NSString *lastResponse = nil;
    for (NSString *response in [responses reverseObjectEnumerator]) {
        if (![response isEqualToString:@""]) {
            lastResponse = response;
            break;
        }
    }

    // 将response按换行分割成行
    NSArray<NSString *> *headerLines = [lastResponse componentsSeparatedByString:@"\r\n"];
    NSInteger statusCode = 0;
    NSString *httpVersion = nil;
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < headerLines.count; i++) {
        NSString *line = headerLines[i];
        // 忽略掉尾部空字符串
        if (![line isEqualToString:@""]) {
            // 分析首行，以空格做分隔
            if (i == 0) {
                NSArray<NSString *> *components = [line componentsSeparatedByString:@" "];
                httpVersion = components[0];
                statusCode = [components[1] integerValue];
            } else {
                // 后续的行以": "做分隔
                NSArray<NSString *> *components = [line componentsSeparatedByString:@": "];
                headers[components[0]] = components[1];
            }
        }
    }
    return [[NSHTTPURLResponse alloc] initWithURL:url statusCode:statusCode HTTPVersion:httpVersion headerFields:headers];
}

// libcurl的write回调函数，用于处理收到的body
static size_t write_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    NSMutableData *data = [[NSMutableData alloc] init];
    [data appendBytes:contents length:size * nmemb];
    NSURLProtocol *protocol = (__bridge NSURLProtocol *)userp;
    [protocol.client URLProtocol:protocol didLoadData:data];
    return size * nmemb;
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
