//
//  EMASCurlProtocol.m
//  EMASCurl
//
//  Created by xin yu on 2024/10/29.
//

#import "EMASCurlProtocol.h"
#import <curl/curl.h>

@interface EMASCurlProtocol()

@property (nonatomic) NSInputStream *inputStream;

@property (nonatomic) CURL *easyHandle;

@end


@implementation EMASCurlProtocol

static Class<EMASCurlProtocolDNSResolver> dnsResolver;

static bool enableHttp2;

static bool enableHttp3;

// runtime 的libcurl xcframework是否支持HTTP2
static bool curlFeatureHttp2;

// runtime 的libcurl xcframework是否支持HTTP3
static bool curlFeatureHttp3;

static bool enableDebugLog;

static NSString *httpProxy;

static NSString *httpsProxy;

#pragma mark * user API

// 拦截使用自定义NSURLSessionConfiguration创建的session发起的requst
+ (void)installIntoSessionConfiguration:(NSURLSessionConfiguration*)sessionConfiguration {
    NSMutableArray *protocolsArray = [NSMutableArray arrayWithArray:sessionConfiguration.protocolClasses];
    [protocolsArray insertObject:self atIndex:0];
    [sessionConfiguration setProtocolClasses:protocolsArray];
}

// 拦截sharedSession发起的request
+ (void)registerCurlProtocol {
    [NSURLProtocol registerClass:self];
}

+ (void)unregisterCurlProtocol {
    [NSURLProtocol unregisterClass:self];
}

+ (void)activateHttp2 {
    // 假如runtime 的libcurl xcframework支持HTTP2，则开启HTTP2
    if (curlFeatureHttp2) {
        enableHttp2 = YES;
    } else {
        enableHttp2 = NO;
    }
}

+ (void)activateHttp3 {
    // 假如runtime 的libcurl xcframework支持HTTP3，则开启HTTP3
    if (curlFeatureHttp3) {
        enableHttp3 = YES;
    } else {
        enableHttp3 = NO;
    }

    [self activateHttp2];
}

+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled {
    enableDebugLog = debugLogEnabled;
}

+ (void)setDNSResolver:(Class<EMASCurlProtocolDNSResolver>)resolver {
    dnsResolver = resolver;
}

#pragma mark * NSURLProtocol overrides

// 在类加载方法中初始化libcurl
+ (void)load {
    curl_global_init(CURL_GLOBAL_DEFAULT);

    // 读取runtime libcurl对于http2/3的支持
    curl_version_info_data *version_info = curl_version_info(CURLVERSION_NOW);
    curlFeatureHttp2 = (version_info->features & CURL_VERSION_HTTP2) ? YES : NO;
    curlFeatureHttp3 = (version_info->features & CURL_VERSION_HTTP3) ? YES : NO;

    enableHttp2 = NO;
    enableHttp3 = NO;
    enableDebugLog = NO;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([[request.URL absoluteString] isEqual:@"about:blank"]) {
        return NO;
    }
    // 不是http或https，则不拦截
    if(!([request.URL.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
         [request.URL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)) {
        return NO;
    }
    return YES;
}

// 无需修改原request
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    CURL *easyHandle = curl_easy_init();
    self.easyHandle = easyHandle;
    if (!easyHandle) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"fail to init easy handle" code:-1 userInfo:nil]];
        return;
    }

    [self populateRequestHeader:easyHandle];
    [self populateRequestBody:easyHandle];

    // 用于存储收到的所有header
    NSMutableData *receivedHeader = [[NSMutableData alloc] init];
    NSError *error = nil;
    [self configEasyHandle:easyHandle receivedHeader:receivedHeader error:&error];
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    // 开始请求
    CURLcode res = curl_easy_perform(easyHandle);
    if (res != CURLE_OK) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"fail to peform curl" code:res userInfo:nil]];
    } else {
        [self.client URLProtocol:self didReceiveResponse:[self convertHeaderToResponse:receivedHeader] cacheStoragePolicy:NSURLCacheStorageAllowed];
        [self.client URLProtocolDidFinishLoading:self];
    }
    curl_easy_cleanup(easyHandle);
    self.easyHandle = nil;
}

- (void)stopLoading {
    if(self.inputStream != nil && [self.inputStream streamStatus] == NSStreamStatusOpen) {
        [self.inputStream close];
        self.inputStream = nil;
    }
    if (self.easyHandle != nil) {
        curl_easy_cleanup(self.easyHandle);
        self.easyHandle = nil;
    }
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
    // 仅https url能使用quic
    if (enableHttp3 && [request.URL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
        // Use HTTP/3, fallback to HTTP/2 or HTTP/1 if needed. For HTTPS only. For HTTP, this option makes libcurl return error.
        curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_3);
    } else if (enableHttp2) {
        // Attempt HTTP 2 requests. libcurl falls back to HTTP 1.1 if HTTP 2 cannot be negotiated with the server.
        curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2);
    } else {
        // 仅使用http1.1
        curl_easy_setopt(easyHandle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
    }

    // 配置支持的HTTP压缩算法，""代表自动检测内置的算法，目前zlib支持deflate与gzip
    curl_easy_setopt(easyHandle, CURLOPT_ACCEPT_ENCODING, "");

    // 将拦截到的request的header字段进行透传
    struct curl_slist *headerFields = convertHeadersToCurlSlist(request.allHTTPHeaderFields);
    curl_easy_setopt(easyHandle, CURLOPT_HTTPHEADER, headerFields);
}

- (void)populateRequestBody:(CURL *)easyHandle {
    NSURLRequest *request = self.request;

    if (![request HTTPBodyStream]) {
        // 处理方法为PUT但是BODY为空的情况，指定Content-Length为0
        if ([@"PUT" isEqualToString:request.HTTPMethod]) {
            curl_easy_setopt(easyHandle, CURLOPT_INFILESIZE_LARGE, 0L);
        } else if ([@"POST" isEqualToString:request.HTTPMethod]) {
            // 处理方法为POST但是BODY为空的情况，指定Content-Length为0
            curl_easy_setopt(easyHandle, CURLOPT_POSTFIELDSIZE_LARGE, 0L);
        }
        return;
    }

    self.inputStream = request.HTTPBodyStream;
    // 用read_cb回调函数来读取需要传输的数据
    curl_easy_setopt(easyHandle, CURLOPT_READFUNCTION, read_cb);
    // self传给read_cb函数的void *userp参数
    curl_easy_setopt(easyHandle, CURLOPT_READDATA, self);

    NSString *contentLength = [request valueForHTTPHeaderField:@"Content-Length"];
    if (!contentLength) {
        return;
    }
    // 如果是PUT，使用PUT的方式指定Content-Length,否则以POST的方式指定
    if ([@"PUT" isEqualToString:request.HTTPMethod]) {
        curl_easy_setopt(easyHandle, CURLOPT_INFILESIZE_LARGE, [contentLength longLongValue]);
    } else if (![@"GET" isEqualToString:request.HTTPMethod] && ![@"HEAD" isEqualToString:request.HTTPMethod]) {
        // 对于POST以及四种基本方法（GET、POST、HEAD、PUT）以外的自定义方法，以POST的方式指定Content-Length
        curl_easy_setopt(easyHandle, CURLOPT_POSTFIELDSIZE_LARGE, [contentLength longLongValue]);
        curl_easy_setopt(easyHandle, CURLOPT_POST, 1);
    }
}

- (void)configEasyHandle:(CURL *)easyHandle receivedHeader:(NSMutableData *)receivedHeader error:(NSError **)error {
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
    // 假如设置了自定义resolve，则使用
    if(dnsResolver) {
        [self configCustomResolve:easyHandle];
    }
    // 设置debug回调函数以输出日志
    if (enableDebugLog) {
        curl_easy_setopt(easyHandle, CURLOPT_VERBOSE, 1L);
        curl_easy_setopt(easyHandle, CURLOPT_DEBUGFUNCTION, debug_cb);
    }

    // 设置header回调函数处理收到的响应的header数据
    curl_easy_setopt(easyHandle, CURLOPT_HEADERFUNCTION, header_cb);
    // receivedHeader会被传给header_cb函数的void *userp参数
    curl_easy_setopt(easyHandle, CURLOPT_HEADERDATA, (__bridge void *)receivedHeader);
    // 设置write回调函数处理收到的响应的body数据
    curl_easy_setopt(easyHandle, CURLOPT_WRITEFUNCTION, write_cb);
    // self会被传给write_cb函数的void *userp
    curl_easy_setopt(easyHandle, CURLOPT_WRITEDATA, (__bridge void *)self);

    // 开启TCP keep alive
    curl_easy_setopt(easyHandle, CURLOPT_TCP_KEEPALIVE, 1L);
    // 开启重定向
    curl_easy_setopt(easyHandle, CURLOPT_FOLLOWLOCATION, 1L);
    // 为了线程安全，设置NOSIGNAL
    curl_easy_setopt(easyHandle, CURLOPT_NOSIGNAL, 1L);
}

- (void)configCustomResolve:(CURL *)easyHandle {
    NSURL *url = self.request.URL;

    NSString *host = [url host];
    NSNumber *port = [url port];

    // 如果没有提供端口号，则 port 可能为 nil
    if (!port) {
        // 根据 URL 的 scheme 来设置默认端口
        if ([url.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame) {
            port = @(80);
        } else if ([url.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
            port = @(443);
        }
    }

    NSString *address = [dnsResolver resolveDomain:host];
    // 解析成功则使用httpdns解析结果，失败则降级
    if (address) {
        NSString *hostPortAddressString = [NSString stringWithFormat:@"+%@:%@:%@", host, port, address];
        curl_easy_setopt(easyHandle, CURLOPT_RESOLVE, curl_slist_append(NULL, [hostPortAddressString UTF8String]));
    }
}

#pragma mark * convert function

// 将拦截到的request中的header字段，转换为一个curl list
struct curl_slist * convertHeadersToCurlSlist(NSDictionary<NSString *, NSString *> *headers) {
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

// 将libcurl收到的header数据，转换为一个NSURLResponse
- (NSURLResponse *)convertHeaderToResponse:(NSMutableData *)receivedHeader {
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
        if(![line isEqualToString:@""]) {
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
    return [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:statusCode HTTPVersion:httpVersion headerFields:headers];
}

#pragma mark * libcurl callback function

// libcurl的header回调函数，用于处理收到的header
size_t header_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    NSMutableData *receivedHeader = (__bridge NSMutableData *)userp;
    [receivedHeader appendBytes:contents length:size * nmemb];
    return size * nmemb;
}

// libcurl的write回调函数，用于处理收到的body
size_t write_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    NSMutableData *data = [[NSMutableData alloc] init];
    [data appendBytes:contents length:size * nmemb];
    NSURLProtocol *protocol = (__bridge NSURLProtocol *)userp;
    [protocol.client URLProtocol:protocol didLoadData:data];
    return size * nmemb;
}

// libcurl的read回调函数，用于post等需要设置body数据的方法
size_t read_cb(char *buffer, size_t size, size_t nitems, void *userp) {
    EMASCurlProtocol *protocol = (__bridge EMASCurlProtocol *)userp;
    // 检查输入流是否已打开，如果未打开则打开
    if ([protocol.inputStream streamStatus] == NSStreamStatusNotOpen) {
        [protocol.inputStream open];
    }
    NSInteger bytesRead = [protocol.inputStream read:(uint8_t *)buffer maxLength:(size * nitems)];
    if (bytesRead == 0) {
        [protocol.inputStream close];
    }
    if (bytesRead < 0) {
        [protocol.client URLProtocol:protocol didFailWithError:[NSError errorWithDomain:@"fail to read data for HTTP body" code:-2 userInfo:nil]];
    }
    return bytesRead;
}

// libcurl的debug回调函数，输出libcurl的运行日志
int debug_cb(CURL *handle, curl_infotype type, char *data, size_t size, void *userptr) {
    switch (type) {
        case CURLINFO_TEXT:
            NSLog(@"[TEXT] %.*s", (int)size, data);
            break;
        case CURLINFO_HEADER_IN:
            NSLog(@"[HEADER_IN] %.*s", (int)size, data);
            break;
        case CURLINFO_HEADER_OUT:
            NSLog(@"[HEADER_OUT] %.*s", (int)size, data);
            break;
        case CURLINFO_DATA_IN:
            NSLog(@"[DATA_IN] %.*s", (int)size, data);
            break;
        case CURLINFO_DATA_OUT:
            NSLog(@"[DATA_OUT] %.*s", (int)size, data);
            break;
        case CURLINFO_SSL_DATA_IN:
            NSLog(@"[SSL_DATA_IN] %.*s", (int)size, data);
            break;
        case CURLINFO_SSL_DATA_OUT:
            NSLog(@"[SSL_DATA_OUT] %.*s", (int)size, data);
            break;
        case CURLINFO_END:
            NSLog(@"[END] %.*s", (int)size, data);
        default:
            break;
    }
    return 0;
}


@end
