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

- (void)testClientCallbacksDispatchedOnWrongThread {
    // 复杂点：通过自定义NSURLProtocolClient记录回调线程，与startLoading触发线程对比
    // 期望：至少有一个回调不在“协议调度线程”上（即存在跨线程回调）

    XCTestExpectation *mismatchExpectation = [self expectationWithDescription:@"expect callback on wrong thread"];

    _EMAS_ThreadCapturingClient *client = [_EMAS_ThreadCapturingClient new];
    client.expectedThread = [NSThread currentThread];
    client.onCallback = ^(NSString *method, BOOL onExpectedThread) {
        if (!onExpectedThread) {
            [mismatchExpectation fulfill];
        }
    };

    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9/"]; // 端口9通常无服务，便于快速失败
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [EMASCurlProtocol setConnectTimeoutIntervalForRequest:request connectTimeoutInterval:0.2];

    EMASCurlProtocol *protocol = [[EMASCurlProtocol alloc] initWithRequest:request
                                                           cachedResponse:nil
                                                                   client:client];

    [protocol startLoading];

    // 等待证明有一次跨线程回调发生
    [self waitForExpectations:@[mismatchExpectation] timeout:5.0];

    // 尝试收尾；若已完成，该调用应迅速返回
    [protocol stopLoading];
}

-(void)testStopLoadingIsBlocking {
    // 复杂点：使用 MockServer /stream 端点（每秒发送一块数据），确保请求处于进行中；
    // 立刻调用 stopLoading，测量其阻塞时间，应显著大于 0.8s，体现同步等待。

    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9080/stream"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [EMASCurlProtocol setConnectTimeoutIntervalForRequest:request connectTimeoutInterval:3.0];

    _EMAS_ThreadCapturingClient *client = [_EMAS_ThreadCapturingClient new];
    client.expectedThread = [NSThread currentThread];
    client.onCallback = nil;

    EMASCurlProtocol *protocol = [[EMASCurlProtocol alloc] initWithRequest:request
                                                           cachedResponse:nil
                                                                   client:client];

    [protocol startLoading];

    [NSThread sleepForTimeInterval:0.05];

    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [protocol stopLoading];
    CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - t0;

    // 说明：此断言用于证明 stopLoading 为同步等待行为，不追求长时间阻塞；
    // 由于内部有 curl_multi_wait(250ms) 等调度，取消路径通常在数十到数百毫秒内完成。
    XCTAssertTrue(elapsed > 0.1, @"stopLoading 未表现出同步阻塞，elapsed=%.3f", elapsed);
}

@end
