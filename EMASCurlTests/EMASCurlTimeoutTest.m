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

// 暴露 SDK 内部的超时归一化方法用于单元测试
@interface EMASCurlProtocol (EMASCurlTimeoutTesting)
- (long)idleTimeoutSecondsForTimeoutInterval:(NSTimeInterval)timeoutInterval;
@end

@interface EMASCurlTimeoutTest : XCTestCase
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation EMASCurlTimeoutTest

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setDebugLogEnabled:YES];

    // 创建 EMASCurl 配置
    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;  // MockServer 9080 端口仅提供明文 HTTP/1.1
    curlConfig.connectTimeoutInterval = 1.0;  // 设置默认连接超时

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;
    config.HTTPShouldSetCookies = YES;
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testConnectTimeout {
    NSURL *url = [NSURL URLWithString:TIMEOUT_TEST_ENDPOINT];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    // \u8fde\u63a5\u8d85\u65f6\u73b0\u5728\u5df2\u7ecf\u5728\u4e0a\u9762\u7684\u914d\u7f6e\u4e2d\u8bbe\u7f6e

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *receivedError = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        receivedError = error;
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");

    XCTAssertNotNil(receivedError, @"Expected timeout error");
    // CURLcode 会被映射成 NSURLError 码，底层错误码通过 EMASCurlErrorCodeKey 透出
    XCTAssertEqual(receivedError.code, NSURLErrorNetworkConnectionLost, @"Expected mapped error code");
    XCTAssertEqualObjects(receivedError.userInfo[@"EMASCurlErrorCodeKey"], @(56), @"Expected CURLE_RECV_ERROR");
}

- (void)testRequestTimeout {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_TIMEOUT_REQUEST]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 1;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *receivedError = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        receivedError = error;
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");

    XCTAssertNotNil(receivedError, @"Expected timeout error");
    XCTAssertEqual(receivedError.code, -1001, @"Expected timeout error code");
}

// 发起一次请求并等待完成，返回 NO 表示等待超过 waitSeconds 仍未回调
- (BOOL)performRequestWithPath:(NSString *)path
               timeoutInterval:(NSTimeInterval)timeoutInterval
                   waitSeconds:(int64_t)waitSeconds
                 receivedError:(NSError **)receivedError {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = timeoutInterval;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *error = nil;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *taskError) {
        error = taskError;
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    BOOL completed = (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, waitSeconds * NSEC_PER_SEC)) == 0);
    if (receivedError) {
        *receivedError = error;
    }
    return completed;
}

// timeoutInterval 为 INFINITY 时不能把正常请求误判为超时。
// /slow/body 会先返回响应头，body 中间停顿 3 秒，足以让低速判定介入。
- (void)testInfiniteTimeoutIntervalDoesNotTriggerFalseTimeout {
    NSError *receivedError = nil;
    BOOL completed = [self performRequestWithPath:PATH_SLOW_BODY
                                  timeoutInterval:INFINITY
                                      waitSeconds:15
                                    receivedError:&receivedError];

    XCTAssertTrue(completed, @"Request did not complete");
    XCTAssertNil(receivedError, @"Expected success but got error: %@", receivedError);
}

// 超大但有限的 timeoutInterval 会被收敛到支持上限，同样不应误判超时。
// 1e16 秒是必须的取值：libcurl 换算毫秒时做 low_speed_time * 1000，
// 只有超过 int64 上限（约 9.2e15 秒）才会溢出成负值，1e12 这类"看着很大"的值并不触发问题。
- (void)testHugeTimeoutIntervalDoesNotTriggerFalseTimeout {
    NSError *receivedError = nil;
    BOOL completed = [self performRequestWithPath:PATH_TIMEOUT_REQUEST
                                  timeoutInterval:1e16
                                      waitSeconds:15
                                    receivedError:&receivedError];

    XCTAssertTrue(completed, @"Request did not complete");
    XCTAssertNil(receivedError, @"Expected success but got error: %@", receivedError);
}

// timeoutInterval 归一化为 libcurl 空闲超时秒数的边界行为。
// 注意：不能通过 NSURLSession 端到端观察这段逻辑——CFNetwork 自身也会按 timeoutInterval
// 计时并抛出 -1001（不带 EMASCurlErrorCodeKey），会先于 libcurl 的秒级低速判定触发。
- (void)testIdleTimeoutNormalization {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:HTTP11_ENDPOINT]];
    EMASCurlProtocol *protocol = [[EMASCurlProtocol alloc] initWithRequest:request
                                                           cachedResponse:nil
                                                                   client:nil];

    // 无法使用的取值：不设置空闲超时
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:0], 0);
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:-5], 0);
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:NAN], 0);

    // 不足 1 秒向上取整，避免截断成 0 而静默失去超时保护
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:0.3], 1);
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:1], 1);
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:60], 60);

    // 超大取值收敛到上限，避免 low_speed_time * 1000 溢出成负值
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:INFINITY], 86400);
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:1e16], 86400);
    XCTAssertEqual([protocol idleTimeoutSecondsForTimeoutInterval:(NSTimeInterval)LONG_MAX], 86400);
}

@end
