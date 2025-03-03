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

    __weak typeof(self) weakSelf = self;

    __block NSNumber *totalTimeConsumed = 0;

    [EMASCurlProtocol setMetricsObserverBlockForRequest:request metricsObserverBlock:^(NSURLRequest * _Nonnull request, BOOL success, NSError * error, double nameLookUpTimeMS, double connectTimeMs, double appConnectTimeMs, double preTransferTimeMs, double startTransferTimeMs, double totalTimeMs) {
        XCTAssertGreaterThan(totalTimeMs, startTransferTimeMs, @"Total time should be after start transfer time");

        // Log metrics for debugging
        NSLog(@"Network Metrics:\n"
              "DNS Lookup: %.2fms\n"
              "Connect: %.2fms\n"
              "App Connect: %.2fms\n"
              "Pre-transfer: %.2fms\n"
              "Start Transfer: %.2fms\n"
              "Total: %.2fms",
              nameLookUpTimeMS, connectTimeMs, appConnectTimeMs,
              preTransferTimeMs, startTransferTimeMs, totalTimeMs);

        totalTimeConsumed = [NSNumber numberWithDouble:totalTimeMs];
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

    [EMASCurlProtocol setMetricsObserverBlockForRequest:request metricsObserverBlock:^(NSURLRequest * _Nonnull request, BOOL success, NSError *error, double nameLookUpTimeMS, double connectTimeMs, double appConnectTimeMs, double preTransferTimeMs, double startTransferTimeMs, double totalTimeMs) {

        // Our mock resolver has a 500ms delay
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
