//
//  EMASCurlDNSResolverTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2024/12/17.
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

static NSURLSession *session;

@interface TestDNSResolver : NSObject <EMASCurlProtocolDNSResolver>
@end

@implementation TestDNSResolver

+ (nullable NSString *)resolveDomain:(nonnull NSString *)domain {
    if ([domain isEqualToString:@"test.emascurl.local"]) {
        return @"127.0.0.1";
    }
    return nil;
}

@end

@interface TestDNSResolverWithFallback : NSObject <EMASCurlProtocolDNSResolver>
@end

@implementation TestDNSResolverWithFallback

+ (nullable NSString *)resolveDomain:(nonnull NSString *)domain {
    if ([domain isEqualToString:@"fallback.emascurl.local"]) {
        // 返回多个IP，第一个是不可访问的10.254.254.254，第二个是可用的127.0.0.1
        return @"10.254.254.254,127.0.0.1";
    }
    return nil;
}

@end

@interface EMASCurlDNSResolverTestBase : XCTestCase
@property (nonatomic, strong) NSMutableData *receivedData;
@end

@implementation EMASCurlDNSResolverTestBase

- (void)setUp {
    [super setUp];
    self.receivedData = [NSMutableData data];
}

- (void)tearDown {
    [super tearDown];
}

- (void)verifyCustomDNSResolutionWithEndpoint:(NSString *)endpoint {
    NSString *testURL = [NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED];

    testURL = [testURL stringByReplacingOccurrencesOfString:@"127.0.0.1" withString:@"test.emascurl.local"];

    NSURL *url = [NSURL URLWithString:testURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Download failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");
        XCTAssertEqual(1024 * 1024, [data length], @"Expected 1MB of data");

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)verifyCustomDNSResolutionWithInvalidDomainAndEndpoint:(NSString *)endpoint {
    NSString *testURL = [NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED];

    testURL = [testURL stringByReplacingOccurrencesOfString:@"127.0.0.1" withString:@"invalid.emascurl.local"];

    NSURL *url = [NSURL URLWithString:testURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 10;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error, @"Expected an error for invalid domain");
        XCTAssertNil(data, @"Should not receive any data");
        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)), 0, @"Request timed out");
}

@end

@interface EMASCurlDNSResolverTestHttp11 : EMASCurlDNSResolverTestBase
@end

@implementation EMASCurlDNSResolverTestHttp11

+ (void)setUp {
    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol setDNSResolver:[TestDNSResolver class]];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config];
}

- (void)testCustomDNSResolution {
    [self verifyCustomDNSResolutionWithEndpoint:HTTP11_ENDPOINT];
}

- (void)testCustomDNSResolutionWithInvalidDomain {
    [self verifyCustomDNSResolutionWithInvalidDomainAndEndpoint:HTTP11_ENDPOINT];
}

- (void)testDNSFallbackToSecondIP {
    // 使用返回多个IP的DNS解析器
    [EMASCurlProtocol setDNSResolver:[TestDNSResolverWithFallback class]];

    NSString *testURL = [NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_ECHO];
    // 替换为测试域名
    testURL = [testURL stringByReplacingOccurrencesOfString:@"127.0.0.1" withString:@"fallback.emascurl.local"];

    NSURL *url = [NSURL URLWithString:testURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *receivedError = nil;
    __block NSHTTPURLResponse *receivedResponse = nil;

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        receivedError = error;
        receivedResponse = (NSHTTPURLResponse *)response;
        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    // 等待请求完成，给予足够的时间让libcurl尝试第一个IP并回退到第二个
    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)), 0, @"Request timed out");

    // 验证请求成功（说明libcurl成功回退到了第二个IP）
    XCTAssertNil(receivedError, @"Request should succeed after falling back to second IP, but got error: %@", receivedError);
    XCTAssertNotNil(receivedResponse, @"Should receive a response");
    XCTAssertEqual(receivedResponse.statusCode, 200, @"Expected 200 status code after DNS fallback");

    // 恢复原来的DNS解析器
    [EMASCurlProtocol setDNSResolver:[TestDNSResolver class]];
}

@end

@interface EMASCurlDNSResolverTestHttp2 : EMASCurlDNSResolverTestBase
@end

@implementation EMASCurlDNSResolverTestHttp2

/// MockServer用的证书没有把域名签进去，只签了127.0.0.1，先不测

@end
