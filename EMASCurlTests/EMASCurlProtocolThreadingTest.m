//
//  EMASCurlProtocolThreadingTest.m
//
//  EMASCurl
//
//  @author Created by Claude Code on 2025/10/21
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurlProtocol.h>

@interface _EMAS_ThreadCapturingClient : NSObject <NSURLProtocolClient>

@property (nonatomic, strong) NSThread *expectedThread;
@property (nonatomic, copy) void (^onCallback)(NSString *method, BOOL onExpectedThread);
@property (nonatomic, strong) NSError *lastError;

@end

@implementation _EMAS_ThreadCapturingClient

- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveResponse:(NSURLResponse *)response cacheStoragePolicy:(NSURLCacheStoragePolicy)policy {
    BOOL ok = ([NSThread currentThread] == self.expectedThread);
    if (self.onCallback) {
        self.onCallback(@"didReceiveResponse", ok);
    }
}

- (void)URLProtocol:(NSURLProtocol *)protocol didLoadData:(NSData *)data {
    BOOL ok = ([NSThread currentThread] == self.expectedThread);
    if (self.onCallback) {
        self.onCallback(@"didLoadData", ok);
    }
}

- (void)URLProtocol:(NSURLProtocol *)protocol didFailWithError:(NSError *)error {
    self.lastError = error;
    BOOL ok = ([NSThread currentThread] == self.expectedThread);
    if (self.onCallback) {
        self.onCallback(@"didFailWithError", ok);
    }
}

- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)protocol {
    BOOL ok = ([NSThread currentThread] == self.expectedThread);
    if (self.onCallback) {
        self.onCallback(@"URLProtocolDidFinishLoading", ok);
    }
}

- (void)URLProtocol:(nonnull NSURLProtocol *)protocol cachedResponseIsValid:(nonnull NSCachedURLResponse *)cachedResponse {
}


- (void)URLProtocol:(nonnull NSURLProtocol *)protocol didCancelAuthenticationChallenge:(nonnull NSURLAuthenticationChallenge *)challenge {
}


- (void)URLProtocol:(nonnull NSURLProtocol *)protocol didReceiveAuthenticationChallenge:(nonnull NSURLAuthenticationChallenge *)challenge {
}


- (void)URLProtocol:(nonnull NSURLProtocol *)protocol wasRedirectedToRequest:(nonnull NSURLRequest *)request redirectResponse:(nonnull NSURLResponse *)redirectResponse {
}


@end

@interface EMASCurlProtocolThreadingTest : XCTestCase
@end

@implementation EMASCurlProtocolThreadingTest

- (void)setUp {
    [super setUp];
    // 关闭缓存影响，确保每次请求路径一致
    [EMASCurlProtocol setCacheEnabled:NO];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testClientCallbacksStayOnDispatchThread {
    XCTestExpectation *terminalExpectation = [self expectationWithDescription:@"expect terminal callback on dispatch thread"];
    __block BOOL sawMismatch = NO;
    __block BOOL fulfilled = NO;

    _EMAS_ThreadCapturingClient *client = [_EMAS_ThreadCapturingClient new];
    client.expectedThread = [NSThread currentThread];
    client.onCallback = ^(NSString *method, BOOL onExpectedThread) {
        if (!onExpectedThread) {
            sawMismatch = YES;
        }
        if (!fulfilled && ([method isEqualToString:@"didFailWithError"] || [method isEqualToString:@"URLProtocolDidFinishLoading"])) {
            fulfilled = YES;
            [terminalExpectation fulfill];
        }
    };

    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9/"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [EMASCurlProtocol setConnectTimeoutIntervalForRequest:request connectTimeoutInterval:0.2];

    EMASCurlProtocol *protocol = [[EMASCurlProtocol alloc] initWithRequest:request
                                                           cachedResponse:nil
                                                                   client:client];

    [protocol startLoading];

    [self waitForExpectations:@[terminalExpectation] timeout:5.0];
    XCTAssertFalse(sawMismatch, @"所有 client 回调都应在调度线程执行");
    [protocol stopLoading];
}

- (void)testStopLoadingReturnsQuicklyAndCancelsOnDispatchThread {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9080/stream"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [EMASCurlProtocol setConnectTimeoutIntervalForRequest:request connectTimeoutInterval:3.0];

    _EMAS_ThreadCapturingClient *client = [_EMAS_ThreadCapturingClient new];
    client.expectedThread = [NSThread currentThread];
    __block BOOL sawMismatch = NO;
    __block BOOL cancelOnExpectedThread = NO;
    XCTestExpectation *cancelExpectation = [self expectationWithDescription:@"expect cancel callback"];
    client.onCallback = ^(NSString *method, BOOL onExpectedThread) {
        if (!onExpectedThread) {
            sawMismatch = YES;
        }
        if ([method isEqualToString:@"didFailWithError"]) {
            cancelOnExpectedThread = onExpectedThread;
            [cancelExpectation fulfill];
        }
    };

    EMASCurlProtocol *protocol = [[EMASCurlProtocol alloc] initWithRequest:request
                                                           cachedResponse:nil
                                                                   client:client];

    [protocol startLoading];

    [NSThread sleepForTimeInterval:0.05];

    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [protocol stopLoading];
    CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - t0;

    XCTAssertLessThan(elapsed, 0.1, @"stopLoading 应尽快返回，elapsed=%.3f", elapsed);
    [self waitForExpectations:@[cancelExpectation] timeout:5.0];
    XCTAssertFalse(sawMismatch, @"取消期间不应出现跨线程回调");
    XCTAssertTrue(cancelOnExpectedThread, @"取消回调必须在调度线程触发");
    XCTAssertEqualObjects(client.lastError.domain, NSURLErrorDomain, @"取消应产生 NSURLErrorDomain 错误");
    XCTAssertEqual(client.lastError.code, NSURLErrorCancelled, @"取消应返回 NSURLErrorCancelled，实际 code=%ld", (long)client.lastError.code);
}

@end
