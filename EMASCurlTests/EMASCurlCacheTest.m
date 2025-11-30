//
//  EMASCurlCacheTest.m
//  EMASCurlTests
//
//  @author Created by Claude Code on 2025-10-09
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

@interface EMASCurlCacheTestBase : XCTestCase
@property (nonatomic, strong) NSURLSession *session;
@end
@implementation EMASCurlCacheTestBase

- (void)setUp {
    [super setUp];
    [[[NSURLCache sharedURLCache] class] respondsToSelector:@selector(sharedURLCache)];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

@end

@interface EMASCurlCacheTestHttp11 : EMASCurlCacheTestBase
@end

@implementation EMASCurlCacheTestHttp11

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setDebugLogEnabled:NO];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;
    curlConfig.maximumCacheableBodyBytes = 128 * 1024; // 128KiB，确保1MB下载不被缓存

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldSetCookies = YES;
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testLargeBodyDoesNotCacheWhenExceedingThreshold {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    [[NSURLCache sharedURLCache] removeCachedResponseForRequest:request];

    XCTestExpectation *exp = [self expectationWithDescription:@"large body fetched"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        XCTAssertEqual(http.statusCode, 200);

        // 验证未写入缓存（超过阈值后内存缓冲被放弃）
        NSCachedURLResponse *cached = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
        XCTAssertNil(cached, @"超过阈值的大响应不应被缓存");
        [exp fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[exp] timeout:15.0];
}

- (void)testNoStoreHeaderDisablesBufferingAndCaching {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_CACHE_NO_STORE]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    XCTestExpectation *exp = [self expectationWithDescription:@"no-store fetched"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        XCTAssertEqual(http.statusCode, 200);

        NSCachedURLResponse *cached = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
        XCTAssertNil(cached, @"no-store 响应不应被缓存");
        [exp fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[exp] timeout:5.0];
}

- (void)testCacheHitReportsMetrics {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_CACHE_CACHEABLE]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    __block BOOL metricsCallbackInvoked = NO;
    __block BOOL isCacheHitMetrics = NO;

    // 设置全局指标观察者
    [EMASCurlProtocol setGlobalTransactionMetricsObserverBlock:^(NSURLRequest * _Nonnull req, BOOL success, NSError * _Nullable error, EMASCurlTransactionMetrics * _Nonnull metrics) {
        metricsCallbackInvoked = YES;
        // 缓存命中时，所有网络时间戳应为nil（除了fetchStartDate和responseEndDate）
        if (metrics.domainLookupStartDate == nil && metrics.connectStartDate == nil) {
            isCacheHitMetrics = YES;
        }
    }];

    // 第一次请求：填充缓存
    XCTestExpectation *firstRequestExp = [self expectationWithDescription:@"first request"];
    NSURLSessionDataTask *task1 = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual(((NSHTTPURLResponse *)response).statusCode, 200);
        [firstRequestExp fulfill];
    }];
    [task1 resume];
    [self waitForExpectations:@[firstRequestExp] timeout:5.0];

    // 重置标志
    metricsCallbackInvoked = NO;
    isCacheHitMetrics = NO;

    // 第二次请求：应命中缓存
    XCTestExpectation *secondRequestExp = [self expectationWithDescription:@"second request cache hit"];
    NSURLSessionDataTask *task2 = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual(((NSHTTPURLResponse *)response).statusCode, 200);
        [secondRequestExp fulfill];
    }];
    [task2 resume];
    [self waitForExpectations:@[secondRequestExp] timeout:5.0];

    // 验证缓存命中时指标回调被调用
    XCTAssertTrue(metricsCallbackInvoked, @"缓存命中时应调用指标回调");
    XCTAssertTrue(isCacheHitMetrics, @"缓存命中的指标应无网络时间戳");

    // 清理
    [EMASCurlProtocol setGlobalTransactionMetricsObserverBlock:nil];
}

// 测试404响应可被缓存（RFC 7234: 404需要显式Cache-Control或Expires）
- (void)testCache404ResponseWithCacheControl {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_CACHE_404]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    // 第一次请求
    XCTestExpectation *firstExp = [self expectationWithDescription:@"first 404 request"];
    NSURLSessionDataTask *task1 = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual(((NSHTTPURLResponse *)response).statusCode, 404);
        [firstExp fulfill];
    }];
    [task1 resume];
    [self waitForExpectations:@[firstExp] timeout:5.0];

    // 验证响应已被缓存
    NSCachedURLResponse *cached = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    XCTAssertNotNil(cached, @"404响应应被缓存（带Cache-Control: max-age）");
}

// 测试410响应可被缓存（RFC 7234: 410默认可缓存）
- (void)testCache410ResponseWithCacheControl {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_CACHE_410]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    // 第一次请求
    XCTestExpectation *firstExp = [self expectationWithDescription:@"first 410 request"];
    NSURLSessionDataTask *task1 = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual(((NSHTTPURLResponse *)response).statusCode, 410);
        [firstExp fulfill];
    }];
    [task1 resume];
    [self waitForExpectations:@[firstExp] timeout:5.0];

    // 验证响应已被缓存
    NSCachedURLResponse *cached = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    XCTAssertNotNil(cached, @"410响应应被缓存（带Cache-Control: max-age）");
}

@end

@interface EMASCurlCacheTestHttp2 : EMASCurlCacheTestBase
@end

@implementation EMASCurlCacheTestHttp2

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setDebugLogEnabled:NO];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.maximumCacheableBodyBytes = 128 * 1024; // 128KiB

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *certPath = [testBundle pathForResource:@"ca" ofType:@"crt"];
    XCTAssertNotNil(certPath);
    curlConfig.caFilePath = certPath;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldSetCookies = YES;
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testLargeBodyDoesNotCacheWhenExceedingThreshold {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP2_ENDPOINT, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    [[NSURLCache sharedURLCache] removeCachedResponseForRequest:request];

    XCTestExpectation *exp = [self expectationWithDescription:@"large body fetched h2"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        XCTAssertEqual(http.statusCode, 200);

        NSCachedURLResponse *cached = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
        XCTAssertNil(cached, @"超过阈值的大响应不应被缓存");
        [exp fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[exp] timeout:20.0];
}

- (void)testNoStoreHeaderDisablesBufferingAndCaching {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP2_ENDPOINT, PATH_CACHE_NO_STORE]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    XCTestExpectation *exp = [self expectationWithDescription:@"no-store fetched h2"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        XCTAssertEqual(http.statusCode, 200);

        NSCachedURLResponse *cached = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
        XCTAssertNil(cached, @"no-store 响应不应被缓存");
        [exp fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[exp] timeout:5.0];
}

@end
