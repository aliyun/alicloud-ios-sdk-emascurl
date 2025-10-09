//
//  EMASCurlCacheTest.m
//  EMASCurlTests
//
//  @author Created by Claude Code on 2025-10-09
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

static NSURLSession *session;

@interface EMASCurlCacheTestBase : XCTestCase
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

+ (void)setUp {
    [EMASCurlProtocol setDebugLogEnabled:NO];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;
    curlConfig.maximumCacheableBodyBytes = 128 * 1024; // 128KiB，确保1MB下载不被缓存

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldSetCookies = YES;
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testLargeBodyDoesNotCacheWhenExceedingThreshold {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    XCTestExpectation *exp = [self expectationWithDescription:@"large body fetched"];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
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

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
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

@interface EMASCurlCacheTestHttp2 : EMASCurlCacheTestBase
@end

@implementation EMASCurlCacheTestHttp2

+ (void)setUp {
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
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testLargeBodyDoesNotCacheWhenExceedingThreshold {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP2_ENDPOINT, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    XCTestExpectation *exp = [self expectationWithDescription:@"large body fetched h2"];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
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

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
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
