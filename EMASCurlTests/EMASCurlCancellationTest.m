//
//  EMASCurlCancellationTest.m
//
//  EMASCurl
//
//  @author Created by Claude Code on 2025/11/30
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

@interface EMASCurlCancellationTest : XCTestCase

@property (nonatomic, strong) NSURLSession *session;

@end

@implementation EMASCurlCancellationTest

- (void)setUp {
    [super setUp];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)tearDown {
    [self.session invalidateAndCancel];
    self.session = nil;
    [super tearDown];
}

#pragma mark - Cancel During Different Phases

- (void)testCancelDuringConnection {
    // 使用延迟响应的端点来测试连接阶段取消
    XCTestExpectation *expectation = [self expectationWithDescription:@"cancel during connection"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_SLOW_HEADERS]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 取消后应收到 cancelled 错误
        XCTAssertNotNil(error, @"Should receive an error after cancellation");
        XCTAssertEqual(error.code, NSURLErrorCancelled, @"Error should be NSURLErrorCancelled");

        [expectation fulfill];
    }];

    [task resume];

    // 立即取消
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [task cancel];
    });

    [self waitForExpectations:@[expectation] timeout:10.0];
}

- (void)testCancelDuringDataTransfer {
    // 使用慢速 body 端点测试数据传输阶段取消
    XCTestExpectation *expectation = [self expectationWithDescription:@"cancel during data transfer"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_SLOW_LONG_BODY]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error, @"Should receive an error after cancellation");
        XCTAssertEqual(error.code, NSURLErrorCancelled, @"Error should be NSURLErrorCancelled");

        [expectation fulfill];
    }];

    [task resume];

    // 等待一段时间后取消（让请求开始传输数据）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [task cancel];
    });

    [self waitForExpectations:@[expectation] timeout:15.0];
}

- (void)testCancelAfterResponseHeadersReceived {
    // 使用慢速 body 端点，头部会快速返回但 body 延迟
    XCTestExpectation *expectation = [self expectationWithDescription:@"cancel after headers"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_SLOW_BODY]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error, @"Should receive an error after cancellation");
        XCTAssertEqual(error.code, NSURLErrorCancelled, @"Error should be NSURLErrorCancelled");

        [expectation fulfill];
    }];

    [task resume];

    // 等待头部返回后取消
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [task cancel];
    });

    [self waitForExpectations:@[expectation] timeout:10.0];
}

#pragma mark - Safety Tests

- (void)testDoubleCancelIsSafe {
    // 测试重复取消的安全性
    XCTestExpectation *expectation = [self expectationWithDescription:@"double cancel"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_SLOW_HEADERS]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    __block BOOL callbackCalled = NO;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 回调只应被调用一次
        XCTAssertFalse(callbackCalled, @"Callback should only be called once");
        callbackCalled = YES;

        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, NSURLErrorCancelled);

        [expectation fulfill];
    }];

    [task resume];

    // 连续取消两次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [task cancel];
        [task cancel];  // 第二次取消不应导致崩溃或重复回调
    });

    [self waitForExpectations:@[expectation] timeout:10.0];
}

- (void)testCancelledErrorCode {
    // 验证取消后的错误码正确
    XCTestExpectation *expectation = [self expectationWithDescription:@"cancelled error code"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_SLOW_HEADERS]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error, @"Error should not be nil");
        XCTAssertEqual(error.code, NSURLErrorCancelled, @"Error code should be NSURLErrorCancelled (-999)");
        XCTAssertEqualObjects(error.domain, NSURLErrorDomain, @"Error domain should be NSURLErrorDomain");

        [expectation fulfill];
    }];

    [task resume];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [task cancel];
    });

    [self waitForExpectations:@[expectation] timeout:10.0];
}

- (void)testCancelBeforeResume {
    // 测试在 resume 之前取消
    XCTestExpectation *expectation = [self expectationWithDescription:@"cancel before resume"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_ECHO]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, NSURLErrorCancelled);
        [expectation fulfill];
    }];

    // 先取消再 resume
    [task cancel];
    [task resume];

    [self waitForExpectations:@[expectation] timeout:5.0];
}

- (void)testCancelImmediatelyAfterResume {
    // 测试在 resume 之后立即取消
    XCTestExpectation *expectation = [self expectationWithDescription:@"cancel immediately after resume"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_SLOW_HEADERS]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, NSURLErrorCancelled);
        [expectation fulfill];
    }];

    [task resume];
    [task cancel];  // 立即取消

    [self waitForExpectations:@[expectation] timeout:5.0];
}

#pragma mark - No Callbacks After Cancellation

- (void)testNoDataReceivedAfterCancellation {
    // 验证取消后不会收到更多数据
    XCTestExpectation *expectation = [self expectationWithDescription:@"no data after cancel"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_SLOW_LONG_BODY]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    __block NSUInteger totalBytesReceived = 0;

    // 使用 delegate 来跟踪数据接收
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];

    NSURLSession *delegateSession = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURLSessionDataTask *task = [delegateSession dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 取消后回调
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, NSURLErrorCancelled);

        // 验证没有收到太多数据（取消应该阻止更多数据）
        XCTAssertTrue(totalBytesReceived < 100, @"Should not receive much data after early cancellation");

        [expectation fulfill];
    }];

    [task resume];

    // 快速取消
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [task cancel];
    });

    [self waitForExpectations:@[expectation] timeout:15.0];

    [delegateSession invalidateAndCancel];
}

@end
