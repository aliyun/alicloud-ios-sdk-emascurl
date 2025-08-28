//
//  EMASLocalHttpProxyConnectionReuseTest.m
//  EMASLocalProxyTests
//
//  测试连接复用和半关闭场景
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASLocalProxy/EMASLocalProxy.h>
#import "EMASLocalProxyTestConstants.h"

static NSURLSession *session;

@interface EMASLocalHttpProxyConnectionReuseTestBase : XCTestCase

@end

@implementation EMASLocalHttpProxyConnectionReuseTestBase

#pragma mark - Helper Methods

/**
 * 执行多个连续请求以测试连接复用
 */
- (void)executeSequentialRequests:(NSString *)endpoint
                             count:(NSInteger)count
                   validationBlock:(void (^)(NSArray<NSHTTPURLResponse *> *responses, NSArray<NSError *> *errors))validationBlock {

    NSMutableArray<NSHTTPURLResponse *> *responses = [NSMutableArray array];
    NSMutableArray<NSError *> *errors = [NSMutableArray array];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_group_t group = dispatch_group_create();

    for (NSInteger i = 0; i < count; i++) {
        dispatch_group_enter(group);

        // 使用小延迟确保请求按顺序发送
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/connection_id?request=%ld", endpoint, (long)i]];
            NSURLRequest *request = [NSURLRequest requestWithURL:url];

            NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                @synchronized(responses) {
                    if (response) {
                        [responses addObject:(NSHTTPURLResponse *)response];
                    }
                    if (error) {
                        [errors addObject:error];
                    } else {
                        [errors addObject:[NSNull null]];
                    }

                    // 记录响应数据用于调试
                    if (data) {
                        NSString *responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        NSLog(@"Request %ld response: %@", (long)i, responseStr);
                    }
                }
                dispatch_group_leave(group);
            }];

            [task resume];
        });
    }

    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (validationBlock) {
            validationBlock(responses, errors);
        }
        dispatch_semaphore_signal(semaphore);
    });

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0,
                   @"Sequential requests timed out");
}

/**
 * 执行并发请求以测试连接池行为
 */
- (void)executeConcurrentRequests:(NSString *)endpoint
                             count:(NSInteger)count
                   validationBlock:(void (^)(NSArray<NSHTTPURLResponse *> *responses, NSArray<NSError *> *errors))validationBlock {

    NSMutableArray<NSHTTPURLResponse *> *responses = [NSMutableArray array];
    NSMutableArray<NSError *> *errors = [NSMutableArray array];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatch_group_t group = dispatch_group_create();

    for (NSInteger i = 0; i < count; i++) {
        dispatch_group_enter(group);

        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/connection_id?request=%ld", endpoint, (long)i]];
        NSURLRequest *request = [NSURLRequest requestWithURL:url];

        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            @synchronized(responses) {
                if (response) {
                    [responses addObject:(NSHTTPURLResponse *)response];
                }
                if (error) {
                    [errors addObject:error];
                } else {
                    [errors addObject:[NSNull null]];
                }

                if (data) {
                    NSString *responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    NSLog(@"Concurrent request %ld response: %@", (long)i, responseStr);
                }
            }
            dispatch_group_leave(group);
        }];

        [task resume];
    }

    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (validationBlock) {
            validationBlock(responses, errors);
        }
        dispatch_semaphore_signal(semaphore);
    });

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0,
                   @"Concurrent requests timed out");
}

/**
 * 测试半关闭后立即复用连接
 */
- (void)executeHalfCloseWithImmediateReuse:(NSString *)endpoint
                            validationBlock:(void (^)(BOOL success, NSString *details))validationBlock {

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL testSuccess = YES;
    __block NSString *testDetails = @"";

    // 第一个请求：触发半关闭
    NSURL *url1 = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_HALF_CLOSE_TEST]];
    NSMutableURLRequest *request1 = [NSMutableURLRequest requestWithURL:url1];
    request1.HTTPMethod = @"POST";
    request1.HTTPBody = [@"Test data for half-close" dataUsingEncoding:NSUTF8StringEncoding];
    [request1 setValue:@"bidirectional" forHTTPHeaderField:@"X-Test-Scenario"];

    NSURLSessionDataTask *task1 = [session dataTaskWithRequest:request1
                                             completionHandler:^(NSData *data1, NSURLResponse *response1, NSError *error1) {
        if (error1) {
            testSuccess = NO;
            testDetails = [NSString stringWithFormat:@"First request failed: %@", error1];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        NSLog(@"First request completed successfully");

        // 立即发送第二个请求到相同端点
        NSURL *url2 = [NSURL URLWithString:[NSString stringWithFormat:@"%@/echo", endpoint]];
        NSURLRequest *request2 = [NSURLRequest requestWithURL:url2];

        NSURLSessionDataTask *task2 = [session dataTaskWithRequest:request2
                                                 completionHandler:^(NSData *data2, NSURLResponse *response2, NSError *error2) {
            if (error2) {
                testSuccess = NO;
                testDetails = [NSString stringWithFormat:@"Second request failed: %@", error2];
            } else {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response2;
                if (httpResponse.statusCode == 200) {
                    testDetails = @"Both requests completed successfully";
                } else {
                    testSuccess = NO;
                    testDetails = [NSString stringWithFormat:@"Unexpected status code: %ld", (long)httpResponse.statusCode];
                }
            }

            if (validationBlock) {
                validationBlock(testSuccess, testDetails);
            }
            dispatch_semaphore_signal(semaphore);
        }];

        [task2 resume];
    }];

    [task1 resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0,
                   @"Half-close reuse test timed out");
}

/**
 * 测试Keep-Alive连接行为
 */
- (void)executeKeepAliveTest:(NSString *)endpoint
              validationBlock:(void (^)(NSArray<NSHTTPURLResponse *> *responses))validationBlock {

    NSMutableArray<NSHTTPURLResponse *> *responses = [NSMutableArray array];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    // 发送多个带Keep-Alive头的请求
    dispatch_group_t group = dispatch_group_create();

    for (NSInteger i = 0; i < 3; i++) {
        dispatch_group_enter(group);

        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/keep_alive_test?request=%ld", endpoint, (long)i]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
        [request setValue:@"timeout=5, max=100" forHTTPHeaderField:@"Keep-Alive"];

        // 使用小延迟确保请求按顺序发送
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                @synchronized(responses) {
                    if (response && !error) {
                        [responses addObject:(NSHTTPURLResponse *)response];

                        if (data) {
                            NSString *responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                            NSLog(@"Keep-Alive request %ld response: %@", (long)i, responseStr);
                        }
                    }
                }
                dispatch_group_leave(group);
            }];

            [task resume];
        });
    }

    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (validationBlock) {
            validationBlock(responses);
        }
        dispatch_semaphore_signal(semaphore);
    });

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0,
                   @"Keep-Alive test timed out");
}

#pragma mark - Test Methods

/**
 * 测试连接在正常请求后的复用行为
 */
- (void)connectionReuseAfterNormalRequestTest:(NSString *)endpoint {
    [self executeSequentialRequests:endpoint
                               count:5
                     validationBlock:^(NSArray<NSHTTPURLResponse *> *responses, NSArray<NSError *> *errors) {
        // 验证所有请求都成功
        XCTAssertEqual(responses.count, 5, @"Should have 5 responses");

        for (NSInteger i = 0; i < errors.count; i++) {
            if (errors[i] != [NSNull null]) {
                XCTFail(@"Request %ld failed: %@", (long)i, errors[i]);
            }
        }

        // 验证所有响应都是200
        for (NSHTTPURLResponse *response in responses) {
            XCTAssertEqual(response.statusCode, 200, @"Expected status 200");
        }

        NSLog(@"Connection reuse test completed: %lu successful requests", (unsigned long)responses.count);
    }];
}

/**
 * 测试并发连接行为
 */
- (void)concurrentConnectionTest:(NSString *)endpoint {
    [self executeConcurrentRequests:endpoint
                               count:10
                     validationBlock:^(NSArray<NSHTTPURLResponse *> *responses, NSArray<NSError *> *errors) {
        // 验证所有并发请求都成功
        XCTAssertEqual(responses.count, 10, @"Should have 10 responses");

        NSInteger successCount = 0;
        for (NSInteger i = 0; i < errors.count; i++) {
            if (errors[i] == [NSNull null]) {
                successCount++;
            }
        }

        XCTAssertEqual(successCount, 10, @"All concurrent requests should succeed");
        NSLog(@"Concurrent connection test completed: %ld successful requests", (long)successCount);
    }];
}

/**
 * 测试半关闭后立即复用
 */
- (void)halfCloseWithImmediateReuseTest:(NSString *)endpoint {
    [self executeHalfCloseWithImmediateReuse:endpoint
                              validationBlock:^(BOOL success, NSString *details) {
        XCTAssertTrue(success, @"Half-close with immediate reuse should succeed: %@", details);
        NSLog(@"Half-close reuse test result: %@", details);
    }];
}

/**
 * 测试Keep-Alive连接
 */
- (void)keepAliveConnectionTest:(NSString *)endpoint {
    [self executeKeepAliveTest:endpoint
                validationBlock:^(NSArray<NSHTTPURLResponse *> *responses) {
        XCTAssertEqual(responses.count, 3, @"Should have 3 Keep-Alive responses");

        for (NSHTTPURLResponse *response in responses) {
            XCTAssertEqual(response.statusCode, 200, @"Expected status 200");

            // 检查响应头中的连接信息
            NSString *connectionHeader = response.allHeaderFields[@"Connection"];
            NSLog(@"Connection header: %@", connectionHeader);
        }

        NSLog(@"Keep-Alive test completed with %lu responses", (unsigned long)responses.count);
    }];
}

@end

#pragma mark - HTTP Tests (Plain Connection)

@interface EMASLocalHttpProxyConnectionReuseTestHTTP : EMASLocalHttpProxyConnectionReuseTestBase

@end

@implementation EMASLocalHttpProxyConnectionReuseTestHTTP

+ (void)setUp {
    // 设置EMASLocalHttpProxy日志级别
    [EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelDebug];

    // 配置DNS解析器
    [EMASLocalHttpProxy setDNSResolverBlock:^NSArray<NSString *> *(NSString *hostname) {
        if ([hostname isEqualToString:@"127.0.0.1"] || [hostname isEqualToString:@"localhost"]) {
            return @[@"127.0.0.1"];
        }
        return nil;
    }];

    // 等待代理服务启动
    int retryCount = 10;
    while (![EMASLocalHttpProxy isProxyReady] && retryCount > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        retryCount--;
    }

    XCTAssertTrue([EMASLocalHttpProxy isProxyReady], @"EMASLocalHttpProxy should be ready");

    // 创建配置了本地代理的URLSession
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;
    config.HTTPShouldSetCookies = YES;
    config.timeoutIntervalForRequest = 30.0;
    config.HTTPMaximumConnectionsPerHost = 6;

    BOOL proxyConfigured = [EMASLocalHttpProxy installIntoUrlSessionConfiguration:config];
    XCTAssertTrue(proxyConfigured, @"Local proxy should be installed successfully");

    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testConnectionReuseAfterNormalRequest {
    [self connectionReuseAfterNormalRequestTest:HTTP_ENDPOINT];
}

- (void)testConcurrentConnections {
    [self concurrentConnectionTest:HTTP_ENDPOINT];
}

- (void)testHalfCloseWithImmediateReuse {
    [self halfCloseWithImmediateReuseTest:HTTP_ENDPOINT];
}

- (void)testKeepAliveConnection {
    [self keepAliveConnectionTest:HTTP_ENDPOINT];
}

@end

#pragma mark - HTTPS Tests (CONNECT Tunnel)

@interface EMASLocalHttpProxyConnectionReuseTestHTTPS : EMASLocalHttpProxyConnectionReuseTestBase <NSURLSessionDelegate>

@end

@implementation EMASLocalHttpProxyConnectionReuseTestHTTPS

+ (void)setUp {
    // 设置EMASLocalHttpProxy日志级别
    [EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelDebug];

    // 配置DNS解析器
    [EMASLocalHttpProxy setDNSResolverBlock:^NSArray<NSString *> *(NSString *hostname) {
        if ([hostname isEqualToString:@"127.0.0.1"] || [hostname isEqualToString:@"localhost"]) {
            return @[@"127.0.0.1"];
        }
        return nil;
    }];

    // 等待代理服务启动
    int retryCount = 10;
    while (![EMASLocalHttpProxy isProxyReady] && retryCount > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        retryCount--;
    }

    XCTAssertTrue([EMASLocalHttpProxy isProxyReady], @"EMASLocalHttpProxy should be ready");

    // 创建配置了本地代理的URLSession
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;
    config.HTTPShouldSetCookies = YES;
    config.timeoutIntervalForRequest = 30.0;
    config.HTTPMaximumConnectionsPerHost = 6;

    BOOL proxyConfigured = [EMASLocalHttpProxy installIntoUrlSessionConfiguration:config];
    XCTAssertTrue(proxyConfigured, @"Local proxy should be installed successfully");

    session = [NSURLSession sessionWithConfiguration:config delegate:[[EMASLocalHttpProxyConnectionReuseTestHTTPS alloc] init] delegateQueue:nil];
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    // 跳过SSL证书验证用于测试
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)testConnectionReuseAfterNormalRequest {
    [self connectionReuseAfterNormalRequestTest:HTTPS_ENDPOINT];
}

- (void)testConcurrentConnections {
    [self concurrentConnectionTest:HTTPS_ENDPOINT];
}

- (void)testHalfCloseWithImmediateReuse {
    [self halfCloseWithImmediateReuseTest:HTTPS_ENDPOINT];
}

- (void)testKeepAliveConnection {
    [self keepAliveConnectionTest:HTTPS_ENDPOINT];
}

@end
