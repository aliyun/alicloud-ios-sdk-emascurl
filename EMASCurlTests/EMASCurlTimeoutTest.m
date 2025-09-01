//
//  EMASCurlTimeoutTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2024/12/25.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

static NSURLSession *session;

@interface EMASCurlTimeoutTest : XCTestCase
@end

@implementation EMASCurlTimeoutTest

+ (void)setUp {
    [super setUp];
    [EMASCurlProtocol setDebugLogEnabled:YES];

    // 创建 EMASCurl 配置
    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.connectTimeoutInterval = 1.0;  // 设置默认连接超时

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;
    config.HTTPShouldSetCookies = YES;
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testConnectTimeout {
    NSURL *url = [NSURL URLWithString:TIMEOUT_TEST_ENDPOINT];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    // \u8fde\u63a5\u8d85\u65f6\u73b0\u5728\u5df2\u7ecf\u5728\u4e0a\u9762\u7684\u914d\u7f6e\u4e2d\u8bbe\u7f6e

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *receivedError = nil;

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        receivedError = error;
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");

    XCTAssertNotNil(receivedError, @"Expected timeout error");
    XCTAssertEqual(receivedError.code, 56, @"Expected timeout error code");
}

- (void)testRequestTimeout {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_TIMEOUT_REQUEST]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 1;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *receivedError = nil;

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        receivedError = error;
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");

    XCTAssertNotNil(receivedError, @"Expected timeout error");
    XCTAssertEqual(receivedError.code, -1001, @"Expected timeout error code");
}

@end
