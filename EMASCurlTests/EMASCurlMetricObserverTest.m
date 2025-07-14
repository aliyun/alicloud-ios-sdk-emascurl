//
//  EMASCurlMetricObserverTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2024/12/17.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

static NSURLSession *session;

@interface EMASCurlMetricsTestBase : XCTestCase

@end

@implementation EMASCurlMetricsTestBase

- (void)setUp {
    [super setUp];
}

- (void)downloadDataWithMetrics:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block NSNumber *totalTimeConsumed = 0;

    // 测试使用新的全局综合性能指标回调
    [EMASCurlProtocol setGlobalTransactionMetricsObserverBlock:^(NSURLRequest * _Nonnull request, BOOL success, NSError * _Nullable error, EMASCurlTransactionMetrics * _Nonnull metrics) {
        XCTAssertNotNil(metrics, @"Metrics should not be nil");
        XCTAssertNotNil(metrics.responseEndDate, @"Response end date should be set");
        XCTAssertNotNil(metrics.fetchStartDate, @"Fetch start date should be set");

        // Calculate total time from date intervals
        NSTimeInterval totalTime = [metrics.responseEndDate timeIntervalSinceDate:metrics.fetchStartDate];
        XCTAssertGreaterThan(totalTime, 0, @"Total time should be positive");

        // Calculate individual phase timings
        NSTimeInterval domainLookupTime = 0;
        NSTimeInterval connectTime = 0;
        NSTimeInterval secureConnectionTime = 0;
        NSTimeInterval requestTime = 0;
        NSTimeInterval responseTime = 0;

        if (metrics.domainLookupStartDate && metrics.domainLookupEndDate) {
            domainLookupTime = [metrics.domainLookupEndDate timeIntervalSinceDate:metrics.domainLookupStartDate];
        }
        if (metrics.connectStartDate && metrics.connectEndDate) {
            connectTime = [metrics.connectEndDate timeIntervalSinceDate:metrics.connectStartDate];
        }
        if (metrics.secureConnectionStartDate && metrics.secureConnectionEndDate) {
            secureConnectionTime = [metrics.secureConnectionEndDate timeIntervalSinceDate:metrics.secureConnectionStartDate];
        }
        if (metrics.requestStartDate && metrics.requestEndDate) {
            requestTime = [metrics.requestEndDate timeIntervalSinceDate:metrics.requestStartDate];
        }
        if (metrics.responseStartDate && metrics.responseEndDate) {
            responseTime = [metrics.responseEndDate timeIntervalSinceDate:metrics.responseStartDate];
        }

        // Log comprehensive metrics for debugging
        NSLog(@"=== 综合性能指标 (EMASCurlTransactionMetrics) ===\n"
              "请求成功: %@\n"
              "错误信息: %@\n"
              "请求URL: %@\n"
              "\n--- 时间戳信息 ---\n"
              "获取开始时间: %@\n"
              "域名解析开始: %@\n"
              "域名解析结束: %@\n"
              "连接开始时间: %@\n"
              "安全连接开始: %@\n"
              "安全连接结束: %@\n"
              "连接结束时间: %@\n"
              "请求开始时间: %@\n"
              "请求结束时间: %@\n"
              "响应开始时间: %@\n"
              "响应结束时间: %@\n"
              "总耗时: %.3fs\n"
              "\n--- 各阶段耗时分析 ---\n"
              "域名解析耗时: %.3fs (%.0fms)\n"
              "TCP连接耗时: %.3fs (%.0fms)\n"
              "SSL/TLS握手耗时: %.3fs (%.0fms)\n"
              "请求发送耗时: %.3fs (%.0fms)\n"
              "响应接收耗时: %.3fs (%.0fms)\n"
              "\n--- 网络协议信息 ---\n"
              "网络协议: %@\n"
              "代理连接: %@\n"
              "连接重用: %@\n"
              "\n--- 传输字节统计 ---\n"
              "请求头字节数: %ld bytes\n"
              "请求体字节数: %ld bytes\n"
              "响应头字节数: %ld bytes\n"
              "响应体字节数: %ld bytes\n"
              "\n--- 网络地址信息 ---\n"
              "本地地址: %@:%ld\n"
              "远程地址: %@:%ld\n"
              "\n--- SSL/TLS信息 ---\n"
              "TLS协议版本: %@\n"
              "TLS密码套件: %@\n"
              "\n--- 网络类型信息 ---\n"
              "========================================",
              success ? @"是" : @"否",
              error ? error.localizedDescription : @"无",
              request.URL.absoluteString,
              metrics.fetchStartDate,
              metrics.domainLookupStartDate,
              metrics.domainLookupEndDate,
              metrics.connectStartDate,
              metrics.secureConnectionStartDate,
              metrics.secureConnectionEndDate,
              metrics.connectEndDate,
              metrics.requestStartDate,
              metrics.requestEndDate,
              metrics.responseStartDate,
              metrics.responseEndDate,
              totalTime,
              domainLookupTime, domainLookupTime * 1000,
              connectTime, connectTime * 1000,
              secureConnectionTime, secureConnectionTime * 1000,
              requestTime, requestTime * 1000,
              responseTime, responseTime * 1000,
              metrics.networkProtocolName ?: @"未知",
              metrics.proxyConnection ? @"是" : @"否",
              metrics.reusedConnection ? @"是" : @"否",
              (long)metrics.requestHeaderBytesSent,
              (long)metrics.requestBodyBytesSent,
              (long)metrics.responseHeaderBytesReceived,
              (long)metrics.responseBodyBytesReceived,
              metrics.localAddress ?: @"未知", (long)metrics.localPort,
              metrics.remoteAddress ?: @"未知", (long)metrics.remotePort,
              metrics.tlsProtocolVersion ?: @"未使用",
              metrics.tlsCipherSuite ?: @"未使用");

        totalTimeConsumed = [NSNumber numberWithDouble:totalTime * 1000]; // Convert to milliseconds
    }];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Download failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");
        XCTAssertEqual(1024 * 1024, [data length], @"Expected 1MB of data");

        XCTAssertGreaterThan([totalTimeConsumed doubleValue], 0, @"Total time should be recorded");

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Download request timed out");

    // 清除全局回调以避免与其他测试干扰
    [EMASCurlProtocol setGlobalTransactionMetricsObserverBlock:nil];
}

@end

@interface EMASCurlMetricsTestHttp11 : EMASCurlMetricsTestBase
@end

@implementation EMASCurlMetricsTestHttp11

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    [EMASCurlProtocol setDebugLogEnabled:YES];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testDownloadDataWithMetrics {
    [self downloadDataWithMetrics:HTTP11_ENDPOINT];
}

@end

@interface EMASCurlMetricsTestHttp2 : EMASCurlMetricsTestBase
@end

@implementation EMASCurlMetricsTestHttp2

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    [EMASCurlProtocol setDebugLogEnabled:YES];

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *certPath = [testBundle pathForResource:@"ca" ofType:@"crt"];
    XCTAssertNotNil(certPath, @"Certificate file not found in test bundle.");
    [EMASCurlProtocol setSelfSignedCAFilePath:certPath];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testDownloadDataWithMetrics {
    [self downloadDataWithMetrics:HTTP2_ENDPOINT];
}

@end

@interface MockDNSResolver : NSObject <EMASCurlProtocolDNSResolver>
@end

@implementation MockDNSResolver

+ (NSString *)resolveDomain:(NSString *)domain {
    // Simulate DNS resolution by sleeping for a known duration
    [NSThread sleepForTimeInterval:2]; // 500ms delay
    return @"127.0.0.1";
}

@end

@interface EMASCurlMetricsTestCustomDNS : EMASCurlMetricsTestBase
@end

@implementation EMASCurlMetricsTestCustomDNS

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol setDNSResolver:[MockDNSResolver class]];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testCustomDNSResolutionMetrics {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block BOOL metricsReceived = NO;

    double startTime = [[NSDate date] timeIntervalSince1970];

    // 测试单请求回调以验证向下兼容性
    [EMASCurlProtocol setMetricsObserverBlockForRequest:request metricsObserverBlock:^(NSURLRequest * _Nonnull request, BOOL success, NSError *error, double nameLookUpTimeMS, double connectTimeMs, double appConnectTimeMs, double preTransferTimeMs, double startTransferTimeMs, double totalTimeMs) {

        // Our mock resolver has a 2000ms delay
        XCTAssertGreaterThanOrEqual(nameLookUpTimeMS, 2000, @"DNS lookup time should be at least 2000ms with mock resolver");
        XCTAssertLessThan(nameLookUpTimeMS, 2100, @"DNS lookup time should not be much more than 2100ms");

        metricsReceived = YES;

        // Log metrics for debugging
        NSLog(@"Custom DNS Resolution Metrics:\n"
              "DNS Lookup: %.2fms\n"
              "Connect: %.2fms\n"
              "Total: %.2fms",
              nameLookUpTimeMS, connectTimeMs, totalTimeMs);
    }];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertTrue(metricsReceived, @"Metrics callback should have been received");
        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    // 确保解析dns的阻塞是发生在另一个线程
    XCTAssertLessThan([[NSDate date] timeIntervalSince1970] - startTime, 0.1);

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Request timed out");
}

@end
