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

    [EMASCurlProtocol setMetricsObserverBlockForRequest:request metricsObserverBlock:^(NSURLRequest * _Nonnull request, double nameLookUpTimeMS, double connectTimeMs, double appConnectTimeMs, double preTransferTimeMs, double startTransferTimeMs, double totalTimeMs) {
        typeof(self) strongSelf = weakSelf;

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
        
        typeof(self) strongSelf = weakSelf;
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
