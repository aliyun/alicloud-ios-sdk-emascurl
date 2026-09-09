//
//  EMASCurlCacheRegressionTest.m
//  EMASCurlTests
//
//  无网络依赖的缓存功能回归。每个用例使用独立的内存缓存，不修改 sharedURLCache。
//  这里只验证响应内容及缓存策略，不据此判断并发生命周期窗口是否已关闭。
//

#import <XCTest/XCTest.h>
#import "EMASCurlResponseCache.h"
#import "NSCachedURLResponse+EMASCurl.h"

/// 只记录公开 NSURLCache 方法的行为；Foundation 命中与 SDK 返回值分别观察。
/// 用例顺序调用 SDK 的同步接口，因此这些计数不需要用于并发线程之间的同步。
@interface EMASCacheRegressionObservedURLCache : NSURLCache
@property (nonatomic, assign) NSUInteger foundationHits;
@property (nonatomic, assign) NSUInteger removalCalls;
- (void)resetObservations;
@end

@implementation EMASCacheRegressionObservedURLCache

- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request {
    NSCachedURLResponse *response = [super cachedResponseForRequest:request];
    if (response) {
        self.foundationHits += 1;
    }
    return response;
}

- (void)removeCachedResponseForRequest:(NSURLRequest *)request {
    self.removalCalls += 1;
    [super removeCachedResponseForRequest:request];
}

- (void)resetObservations {
    self.foundationHits = 0;
    self.removalCalls = 0;
}

@end

@interface EMASCurlCacheRegressionTest : XCTestCase
@property (nonatomic, strong) NSURL *cacheDirectory;
@property (nonatomic, strong) EMASCacheRegressionObservedURLCache *urlCache;
@property (nonatomic, strong) EMASCurlResponseCache *responseCache;
@end

@implementation EMASCurlCacheRegressionTest

- (void)setUp {
    [super setUp];

    NSString *directoryName = [@"emascurl-cache-regression-" stringByAppendingString:NSUUID.UUID.UUIDString];
    self.cacheDirectory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:directoryName]
                                    isDirectory:YES];
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtURL:self.cacheDirectory
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
    XCTAssertTrue(created, @"创建独立缓存目录失败：%@", error);

    // 禁用磁盘缓存，避免把磁盘写回或删除的时序当成 SDK 同步接口的约定。
    if (@available(iOS 13.0, *)) {
        self.urlCache = [[EMASCacheRegressionObservedURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024
                                                                            diskCapacity:0
                                                                            directoryURL:self.cacheDirectory];
    } else {
        self.urlCache = [[EMASCacheRegressionObservedURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024
                                                                            diskCapacity:0
                                                                                diskPath:self.cacheDirectory.path];
    }
    self.responseCache = [EMASCurlResponseCache new];
    // 注入 SDK 自己的 urlCache 属性，不访问 Foundation 私有 API。
    [self.responseCache setValue:self.urlCache forKey:@"urlCache"];
    XCTAssertEqual([self.responseCache valueForKey:@"urlCache"], self.urlCache);
}

- (void)tearDown {
    [self.urlCache removeAllCachedResponses];
    self.responseCache = nil;
    self.urlCache = nil;
    if (self.cacheDirectory) {
        [[NSFileManager defaultManager] removeItemAtURL:self.cacheDirectory error:NULL];
    }
    self.cacheDirectory = nil;
    [super tearDown];
}

- (NSURLRequest *)requestForPath:(NSString *)path {
    NSURL *url = [NSURL URLWithString:[@"https://cache-regression.invalid/" stringByAppendingString:path]];
    return [NSURLRequest requestWithURL:url];
}

- (NSData *)body {
    return [@"cache regression body" dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSHTTPURLResponse *)responseForRequest:(NSURLRequest *)request
                                   body:(NSData *)body
                                headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *fields = [@{
        @"Content-Type": @"text/plain; charset=utf-8",
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)body.length]
    } mutableCopy];
    [fields addEntriesFromDictionary:headers];
    return [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                     statusCode:200
                                    HTTPVersion:@"HTTP/1.1"
                                   headerFields:[fields copy]];
}

/// 外部通过 Foundation 写入，但提供 SDK 计算响应年龄所需的存储时间戳。
/// 用历史时间戳构造过期响应，避免依赖 sleep 或测试执行速度。
- (void)storeExternalResponseForRequest:(NSURLRequest *)request
                                  body:(NSData *)body
                               headers:(NSDictionary<NSString *, NSString *> *)headers
                     storageTimestamp:(NSTimeInterval)storageTimestamp {
    NSHTTPURLResponse *response = [self responseForRequest:request body:body headers:headers];
    NSCachedURLResponse *cached = [[NSCachedURLResponse alloc] initWithResponse:response
                                                                        data:body
                                                                    userInfo:@{
        EMASUserInfoKeyStorageTimestamp: @(storageTimestamp),
        EMASUserInfoKeyOriginalHTTPVersion: @"HTTP/1.1",
        EMASUserInfoKeyOriginalStatusCode: @200
    }
                                                               storagePolicy:NSURLCacheStorageAllowed];
    [self.urlCache storeCachedResponse:cached forRequest:request];
    [self.urlCache resetObservations];
}

- (void)testFreshExternalResponseIsReturnedWithoutRemoval {
    NSURLRequest *request = [self requestForPath:@"external-fresh"];
    NSData *body = [self body];
    [self storeExternalResponseForRequest:request
                                    body:body
                                 headers:@{@"Cache-Control": @"max-age=600"}
                       storageTimestamp:NSDate.date.timeIntervalSince1970];

    NSCachedURLResponse *returned = [self.responseCache cachedResponseForRequest:request];

    XCTAssertEqual(self.urlCache.foundationHits, (NSUInteger)1, @"必须先确认 Foundation 实际命中");
    XCTAssertNotNil(returned, @"有效的外部写入夹具不应被 SDK 误判为过期");
    XCTAssertEqualObjects(returned.data, body);
    XCTAssertTrue([returned emas_isResponseStillFreshForRequest:request]);
    XCTAssertEqual(self.urlCache.removalCalls, (NSUInteger)0);
}

- (void)testSDKStoreAndLookupPreserveBodyAndHeaders {
    NSURLRequest *request = [self requestForPath:@"sdk-round-trip"];
    NSData *body = [self body];
    NSHTTPURLResponse *response = [self responseForRequest:request body:body headers:@{
        @"Cache-Control": @"max-age=600",
        @"ETag": @"\"sdk-v1\""
    }];
    [self.responseCache cacheResponse:response data:body forRequest:request withHTTPVersion:@"HTTP/1.1"];
    [self.urlCache resetObservations];

    NSCachedURLResponse *returned = [self.responseCache cachedResponseForRequest:request];

    XCTAssertNotNil(returned);
    XCTAssertEqualObjects(returned.data, body);
    XCTAssertTrue([returned.response isKindOfClass:NSHTTPURLResponse.class]);
    NSHTTPURLResponse *returnedHTTP = (NSHTTPURLResponse *)returned.response;
    XCTAssertEqual(returnedHTTP.statusCode, (NSInteger)200);
    XCTAssertEqualObjects(returnedHTTP.URL, request.URL);
    XCTAssertEqualObjects(returnedHTTP.allHeaderFields, response.allHeaderFields);
    XCTAssertEqualObjects([returned emas_etag], @"\"sdk-v1\"");
    XCTAssertTrue([returned emas_isResponseStillFreshForRequest:request]);
    XCTAssertEqual(self.urlCache.foundationHits, (NSUInteger)1);
    XCTAssertEqual(self.urlCache.removalCalls, (NSUInteger)0);
}

- (void)testExpiredResponseWithETagRemainsAvailableForRevalidation {
    NSURLRequest *request = [self requestForPath:@"expired-with-validator"];
    NSData *body = [self body];
    [self storeExternalResponseForRequest:request body:body headers:@{
        @"Cache-Control": @"max-age=600",
        @"ETag": @"\"stale-v1\""
    } storageTimestamp:NSDate.date.timeIntervalSince1970 - 3600];

    NSCachedURLResponse *returned = [self.responseCache cachedResponseForRequest:request];

    XCTAssertEqual(self.urlCache.foundationHits, (NSUInteger)1);
    XCTAssertNotNil(returned, @"过期且带验证器的条目应保留给条件请求使用");
    XCTAssertFalse([returned emas_isResponseStillFreshForRequest:request]);
    XCTAssertEqualObjects([returned emas_etag], @"\"stale-v1\"");
    XCTAssertEqualObjects(returned.data, body);
    XCTAssertEqual(self.urlCache.removalCalls, (NSUInteger)0);
}

- (void)test304UpdatePreservesBodyAndRefreshesHeaders {
    NSURLRequest *request = [self requestForPath:@"revalidate-304"];
    NSData *body = [self body];
    NSHTTPURLResponse *response = [self responseForRequest:request body:body headers:@{
        @"Cache-Control": @"max-age=0",
        @"ETag": @"\"old-v1\""
    }];
    [self.responseCache cacheResponse:response data:body forRequest:request withHTTPVersion:@"HTTP/1.1"];
    NSDictionary *newHeaders = @{
        @"Cache-Control": @"max-age=600",
        @"ETag": @"\"new-v2\"",
        @"Last-Modified": @"Wed, 21 Oct 2015 07:28:00 GMT"
    };

    NSCachedURLResponse *updated = [self.responseCache updateCachedResponseWithHeaders:newHeaders forRequest:request];
    NSCachedURLResponse *stored = [self.responseCache cachedResponseForRequest:request];

    XCTAssertNotNil(updated);
    XCTAssertNotNil(stored, @"304 更新后的响应应能再次从缓存读出");
    if (!updated || !stored) {
        return;
    }
    NSMutableDictionary *expectedHeaders = [response.allHeaderFields mutableCopy];
    [expectedHeaders addEntriesFromDictionary:newHeaders];
    for (NSCachedURLResponse *candidate in @[updated, stored]) {
        XCTAssertEqualObjects(candidate.data, body, @"304 不应丢失原响应体");
        NSHTTPURLResponse *candidateHTTP = (NSHTTPURLResponse *)candidate.response;
        XCTAssertEqual(candidateHTTP.statusCode, (NSInteger)200, @"合成响应应保留原状态码");
        XCTAssertEqualObjects(candidateHTTP.URL, request.URL);
        XCTAssertEqualObjects(candidateHTTP.allHeaderFields, expectedHeaders);
        XCTAssertEqualObjects([candidate emas_etag], @"\"new-v2\"");
        XCTAssertTrue([candidate emas_isResponseStillFreshForRequest:request]);
    }
}

- (void)testExpiredResponseWithoutValidatorReturnsNil {
    NSURLRequest *request = [self requestForPath:@"expired-without-validator"];
    [self storeExternalResponseForRequest:request
                                    body:[self body]
                                 headers:@{@"Cache-Control": @"max-age=600"}
                       storageTimestamp:NSDate.date.timeIntervalSince1970 - 3600];

    NSCachedURLResponse *returned = [self.responseCache cachedResponseForRequest:request];

    XCTAssertEqual(self.urlCache.foundationHits, (NSUInteger)1, @"SDK 返回 nil 与 Foundation 未命中必须区分");
    XCTAssertNil(returned);
    XCTAssertEqual(self.urlCache.removalCalls, (NSUInteger)1);
    // 不断言 Foundation 立即清除条目；这里只验证 SDK 发出移除请求并拒绝返回过期内容。
}

@end
