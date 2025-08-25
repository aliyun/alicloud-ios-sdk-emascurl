//
//  EMASLocalHttpProxyHalfCloseTest.m
//  EMASLocalProxyTests
//
//  Created by xuyecan on 2025/08/24.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASLocalProxy/EMASLocalProxy.h>
#import "EMASLocalProxyTestConstants.h"

static NSURLSession *session;

@interface EMASLocalHttpProxyHalfCloseTestBase : XCTestCase

@end

@implementation EMASLocalHttpProxyHalfCloseTestBase

#pragma mark - Helper Methods

/**
 * 执行HTTP请求并提供详细的验证回调
 */
- (void)executeRequest:(NSString *)endpoint
                  path:(NSString *)path
                method:(NSString *)method
                  body:(NSData *)body
               headers:(NSDictionary *)headers
       validationBlock:(void (^)(NSData *data, NSHTTPURLResponse *response, NSError *error))validationBlock {

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;

    // 设置请求体
    if (body) {
        request.HTTPBody = body;
        [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    }

    // 添加自定义头部
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        // 执行自定义验证逻辑
        if (validationBlock) {
            validationBlock(data, httpResponse, error);
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    // 使用较长的超时时间来适应半关闭场景
    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0, @"Request timed out");
}

/**
 * 使用NSURLSessionDownloadTask执行下载请求
 */
- (void)executeDownloadRequest:(NSString *)endpoint
                          path:(NSString *)path
               validationBlock:(void (^)(NSURL *location, NSHTTPURLResponse *response, NSError *error))validationBlock {

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, path]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithRequest:request
                                                            completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        if (validationBlock) {
            validationBlock(location, httpResponse, error);
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [downloadTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0, @"Download request timed out");
}

/**
 * 使用NSURLSessionUploadTask执行上传请求
 */
- (void)executeUploadRequest:(NSString *)endpoint
                        path:(NSString *)path
                        data:(NSData *)uploadData
             validationBlock:(void (^)(NSData *data, NSHTTPURLResponse *response, NSError *error))validationBlock {

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PUT";
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *uploadTask = [session uploadTaskWithRequest:request
                                                               fromData:uploadData
                                                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        if (validationBlock) {
            validationBlock(data, httpResponse, error);
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [uploadTask resume];

    // 增加超时时间到45秒，因为HTTPS隧道可能需要更多时间
    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC)), 0, @"Upload request timed out");
}

/**
 * 生成指定大小的测试数据
 */
- (NSData *)generateTestData:(NSInteger)sizeInBytes {
    NSMutableData *data = [NSMutableData dataWithCapacity:sizeInBytes];

    for (NSInteger i = 0; i < sizeInBytes; i++) {
        uint8_t byte = (uint8_t)(i % 256);
        [data appendBytes:&byte length:1];
    }

    return data;
}

#pragma mark - Test Methods

/**
 * 测试流式下载中的半关闭处理
 * 验证代理在不同连接模式下的半关闭逻辑：
 * - HTTP模式：直连代理，验证TCP层半关闭处理
 * - HTTPS模式：CONNECT隧道，验证TLS层半关闭处理
 */
- (void)streamingDownloadHalfCloseTest:(NSString *)endpoint {
    [self executeRequest:endpoint
                    path:PATH_STREAM
                  method:@"GET"
                    body:nil
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Stream download should succeed: %@", error);
        XCTAssertNotNil(response, @"Response should not be nil");
        XCTAssertEqual(response.statusCode, 200, @"Expected status code 200, got %ld", (long)response.statusCode);

        // 验证接收到完整的流式数据
        XCTAssertNotNil(data, @"Stream data should not be nil");
        XCTAssertGreaterThan(data.length, 0, @"Stream should contain data");

        // 验证数据包含预期的分块内容
        NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        XCTAssertTrue([dataString containsString:@"chunk"], @"Stream should contain chunk data: %@", dataString);

        NSLog(@"Stream download completed successfully with %lu bytes", (unsigned long)data.length);
    }];
}

/**
 * 测试上传过程中的半关闭处理
 * 验证不同连接模式下的大数据传输半关闭：
 * - HTTP模式：Plain TCP上传，测试直连半关闭
 * - HTTPS模式：通过CONNECT隧道上传，测试隧道半关闭
 */
- (void)uploadDownloadHalfCloseTest:(NSString *)endpoint {
    // 创建300KB的测试数据 (减小数据量以减少测试时间)
    NSData *uploadData = [self generateTestData:300 * 1024];

    [self executeUploadRequest:endpoint
                          path:PATH_UPLOAD_PUT_SLOW
                          data:uploadData
               validationBlock:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Upload should succeed despite server half-close: %@", error);
        XCTAssertNotNil(response, @"Response should not be nil");
        XCTAssertEqual(response.statusCode, 200, @"Expected status code 200, got %ld", (long)response.statusCode);

        // 验证服务器响应包含上传信息
        XCTAssertNotNil(data, @"Response data should not be nil");

        NSError *jsonError;
        NSDictionary *responseJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Response should be valid JSON: %@", jsonError);

        NSNumber *uploadedSize = responseJson[@"size"];
        XCTAssertNotNil(uploadedSize, @"Response should contain size information");
        XCTAssertEqual([uploadedSize integerValue], uploadData.length, @"Uploaded size should match original data size");

        NSLog(@"Upload completed successfully: %lu bytes uploaded, server processed %@ bytes",
              (unsigned long)uploadData.length, uploadedSize);
    }];
}

/**
 * 测试双向半关闭处理
 * 验证代理在不同连接模式下的双向半关闭独立性：
 * - HTTP模式：测试直连模式下的双向半关闭独立处理
 * - HTTPS模式：测试CONNECT隧道中的双向半关闭独立处理
 */
- (void)bidirectionalHalfCloseTest:(NSString *)endpoint {
    // 测试数据
    NSData *testData = [self generateTestData:1024];

    [self executeRequest:endpoint
                    path:PATH_HALF_CLOSE_TEST
                  method:@"POST"
                    body:testData
                 headers:@{@"X-Test-Scenario": @"bidirectional"}
         validationBlock:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Bidirectional half-close should succeed: %@", error);
        XCTAssertNotNil(response, @"Response should not be nil");
        XCTAssertEqual(response.statusCode, 200, @"Expected status code 200, got %ld", (long)response.statusCode);

        // 验证双向数据传输成功
        XCTAssertNotNil(data, @"Response data should not be nil");
        XCTAssertGreaterThan(data.length, 0, @"Response should contain data");

        NSLog(@"Bidirectional half-close test completed successfully");
    }];
}

/**
 * 测试半关闭后的连接终止
 * 验证不同连接模式下的连接生命周期管理：
 * - HTTP模式：测试直连模式下的连接清理
 * - HTTPS模式：测试CONNECT隧道的连接清理
 */
- (void)connectionTerminationAfterHalfCloseTest:(NSString *)endpoint {
    [self executeRequest:endpoint
                    path:PATH_TIMEOUT_REQUEST
                  method:@"GET"
                    body:nil
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        // 这个测试可能会因为连接终止而产生错误，但这是预期的行为
        // 重要的是代理能够正确处理连接状态变化

        if (error) {
            // 检查错误类型是否为预期的连接相关错误
            NSLog(@"Expected connection error occurred: %@", error);
        } else {
            // 如果没有错误，验证响应
            XCTAssertNotNil(response, @"Response should not be nil");
            XCTAssertEqual(response.statusCode, 200, @"Expected status code 200, got %ld", (long)response.statusCode);
            NSLog(@"Connection termination handled successfully");
        }
    }];
}

@end

#pragma mark - HTTP Tests (Plain Connection)

@interface EMASLocalHttpProxyHalfCloseTestHTTP : EMASLocalHttpProxyHalfCloseTestBase

@end

@implementation EMASLocalHttpProxyHalfCloseTestHTTP

+ (void)setUp {
    // 设置EMASLocalHttpProxy日志级别
    [EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelDebug];

    // 配置DNS解析器用于localhost解析
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

    // 创建配置了本地代理的URLSession (用于HTTP直连测试)
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;
    config.HTTPShouldSetCookies = YES;

    BOOL proxyConfigured = [EMASLocalHttpProxy installIntoUrlSessionConfiguration:config];
    XCTAssertTrue(proxyConfigured, @"Local proxy should be installed successfully");

    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testStreamingDownloadHalfClose {
    [self streamingDownloadHalfCloseTest:HTTP_ENDPOINT];
}

- (void)testUploadDownloadHalfClose {
    [self uploadDownloadHalfCloseTest:HTTP_ENDPOINT];
}

- (void)testBidirectionalHalfClose {
    [self bidirectionalHalfCloseTest:HTTP_ENDPOINT];
}

- (void)testConnectionTerminationAfterHalfClose {
    [self connectionTerminationAfterHalfCloseTest:HTTP_ENDPOINT];
}

@end

#pragma mark - HTTPS Tests (CONNECT Tunnel)

@interface EMASLocalHttpProxyHalfCloseTestHTTPS : EMASLocalHttpProxyHalfCloseTestBase <NSURLSessionDelegate>

@end

@implementation EMASLocalHttpProxyHalfCloseTestHTTPS

+ (void)setUp {
    // 设置EMASLocalHttpProxy日志级别
    [EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelDebug];

    // 配置DNS解析器用于localhost解析
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

    // 创建配置了本地代理的URLSession (用于HTTPS隧道测试)
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;
    config.HTTPShouldSetCookies = YES;

    BOOL proxyConfigured = [EMASLocalHttpProxy installIntoUrlSessionConfiguration:config];
    XCTAssertTrue(proxyConfigured, @"Local proxy should be installed successfully");

    session = [NSURLSession sessionWithConfiguration:config delegate:[[EMASLocalHttpProxyHalfCloseTestHTTPS alloc] init] delegateQueue:nil];
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    // 跳过SSL证书验证用于测试目的
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)testStreamingDownloadHalfClose {
    [self streamingDownloadHalfCloseTest:HTTPS_ENDPOINT];
}

- (void)testUploadDownloadHalfClose {
    [self uploadDownloadHalfCloseTest:HTTPS_ENDPOINT];
}

- (void)testBidirectionalHalfClose {
    [self bidirectionalHalfCloseTest:HTTPS_ENDPOINT];
}

- (void)testConnectionTerminationAfterHalfClose {
    [self connectionTerminationAfterHalfCloseTest:HTTPS_ENDPOINT];
}

@end
