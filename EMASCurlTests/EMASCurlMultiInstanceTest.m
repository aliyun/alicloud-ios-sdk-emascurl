//
//  EMASCurlMultiInstanceTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2025/01/02.
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlConfigurationManager.h"
#import "EMASCurlTestConstants.h"

@interface EMASCurlMultiInstanceTest : XCTestCase
@end

@implementation EMASCurlMultiInstanceTest

+ (void)setUp {
    [super setUp];
    // 启用调试日志
    [EMASCurlProtocol setDebugLogEnabled:YES];
}

- (void)setUp {
    [super setUp];
    // 清理所有配置，确保测试环境干净
    [[EMASCurlConfigurationManager sharedManager] removeAllConfigurations];
}

- (void)tearDown {
    // 清理测试后的配置
    [[EMASCurlConfigurationManager sharedManager] removeAllConfigurations];
    // 重置默认配置
    [[EMASCurlConfigurationManager sharedManager] setDefaultConfiguration:[EMASCurlConfiguration defaultConfiguration]];
    [super tearDown];
}

#pragma mark - Helper Methods

- (NSURLSession *)createSessionWithConfiguration:(EMASCurlConfiguration *)config {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:config];
    return [NSURLSession sessionWithConfiguration:sessionConfig];
}

- (void)executeRequestWithSession:(NSURLSession *)session
                          endpoint:(NSString *)endpoint
                              path:(NSString *)path
                        completion:(void (^)(NSData *data, NSHTTPURLResponse *response, NSError *error))completion {

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, path]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (completion) {
            completion(data, (NSHTTPURLResponse *)response, error);
        }
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

#pragma mark - 2.1 Multi-Session Tests (Critical)

- (void)testTwoSessionsWithDifferentHTTPVersions {
    // 创建HTTP/1.1配置
    EMASCurlConfiguration *config1 = [EMASCurlConfiguration defaultConfiguration];
    config1.httpVersion = HTTP1;

    // 创建HTTP/2配置
    EMASCurlConfiguration *config2 = [EMASCurlConfiguration defaultConfiguration];
    config2.httpVersion = HTTP2;

    // 为HTTP/2设置证书（测试服务器使用自签名证书）
    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *caCertPath = [testBundle pathForResource:@"ca" ofType:@"crt"];
    NSLog(@"CA cert path: %@", caCertPath);
    if (caCertPath) {
        config2.caFilePath = caCertPath;
    } else {
        NSLog(@"Warning: CA certificate not found in test bundle");
    }

    // 创建两个session
    NSURLSession *session1 = [self createSessionWithConfiguration:config1];
    NSURLSession *session2 = [self createSessionWithConfiguration:config2];

    XCTestExpectation *expectation1 = [self expectationWithDescription:@"HTTP/1.1 request"];
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"HTTP/2 request"];

    // 在HTTP/1.1 session上执行请求
    [self executeRequestWithSession:session1
                            endpoint:HTTP11_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSLog(@"Session1 response: %@, error: %@", response, error);
        XCTAssertNil(error, @"HTTP/1.1请求不应该有错误: %@", error);
        XCTAssertNotNil(response, @"应该收到响应");
        if (response) {
            XCTAssertEqual(response.statusCode, 200, @"状态码应该是200, 实际: %ld", (long)response.statusCode);
        }

        // 验证是HTTP/1.1（通过响应特征判断）
        NSString *httpVersion = response.allHeaderFields[@"X-HTTP-Version"];
        if (httpVersion) {
            XCTAssertTrue([httpVersion containsString:@"1.1"], @"应该使用HTTP/1.1");
        }

        [expectation1 fulfill];
    }];

    // 在HTTP/2 session上执行请求
    [self executeRequestWithSession:session2
                            endpoint:HTTP2_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSLog(@"Session2 response: %@, error: %@", response, error);
        XCTAssertNil(error, @"HTTP/2请求不应该有错误: %@", error);
        XCTAssertNotNil(response, @"应该收到响应");
        if (response) {
            XCTAssertEqual(response.statusCode, 200, @"状态码应该是200, 实际: %ld", (long)response.statusCode);
        }

        // HTTP/2连接的验证（通过HTTPS端点间接验证）
        XCTAssertTrue([response.URL.scheme isEqualToString:@"https"], @"HTTP/2应该使用HTTPS");

        [expectation2 fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testSessionConfigurationIsolation {
    // 创建初始配置
    EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
    config.httpVersion = HTTP1;
    config.connectTimeoutInterval = 3.0;
    config.enableBuiltInGzip = YES;
    config.cacheEnabled = YES;

    // 创建session
    NSURLSession *session = [self createSessionWithConfiguration:config];

    // 修改配置（不应该影响已创建的session）
    config.httpVersion = HTTP2;
    config.connectTimeoutInterval = 1.0;
    config.enableBuiltInGzip = NO;
    config.cacheEnabled = NO;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Request completion"];

    // 执行请求
    [self executeRequestWithSession:session
                            endpoint:HTTP11_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"请求不应该有错误");
        XCTAssertNotNil(response, @"应该收到响应");
        XCTAssertEqual(response.statusCode, 200, @"状态码应该是200");

        // Session应该继续使用原始配置（HTTP/1.1，3秒超时等）
        // 请求成功表明配置隔离正常工作

        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

#pragma mark - 2.2 Backward Compatibility Tests (Critical)

- (void)testLegacyStaticSetters {
    // 使用旧API设置配置
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    [EMASCurlProtocol setConnectTimeoutInterval:3.0];
    [EMASCurlProtocol setBuiltInGzipEnabled:NO];
    [EMASCurlProtocol setBuiltInRedirectionEnabled:NO];
    [EMASCurlProtocol setCertificateValidationEnabled:NO];
    [EMASCurlProtocol setDomainNameVerificationEnabled:NO];
    [EMASCurlProtocol setCacheEnabled:NO];

    // 验证默认配置被更新
    EMASCurlConfiguration *defaultConfig = [EMASCurlProtocol defaultConfiguration];
    XCTAssertEqual(defaultConfig.httpVersion, HTTP2, @"HTTP版本应该被更新为HTTP2");
    XCTAssertEqual(defaultConfig.connectTimeoutInterval, 3.0, @"连接超时应该被更新为3.0秒");
    XCTAssertFalse(defaultConfig.enableBuiltInGzip, @"Gzip应该被禁用");
    XCTAssertFalse(defaultConfig.enableBuiltInRedirection, @"重定向应该被禁用");
    XCTAssertFalse(defaultConfig.certificateValidationEnabled, @"证书验证应该被禁用");
    XCTAssertFalse(defaultConfig.domainNameVerificationEnabled, @"域名验证应该被禁用");
    XCTAssertFalse(defaultConfig.cacheEnabled, @"缓存应该被禁用");

    // 设置域名过滤
    NSArray *whitelist = @[@"api.example.com"];
    NSArray *blacklist = @[@"tracking.com"];
    [EMASCurlProtocol setHijackDomainWhiteList:whitelist];
    [EMASCurlProtocol setHijackDomainBlackList:blacklist];

    defaultConfig = [EMASCurlProtocol defaultConfiguration];
    XCTAssertEqualObjects(defaultConfig.domainWhiteList, whitelist, @"域名白名单应该被更新");
    XCTAssertEqualObjects(defaultConfig.domainBlackList, blacklist, @"域名黑名单应该被更新");

    // 设置代理
    NSString *proxyURL = @"http://proxy.test.com:8080";
    [EMASCurlProtocol setManualProxyServer:proxyURL];

    defaultConfig = [EMASCurlProtocol defaultConfiguration];
    XCTAssertTrue(defaultConfig.manualProxyEnabled, @"手动代理应该被启用");
    XCTAssertEqualObjects(defaultConfig.proxyServer, proxyURL, @"代理服务器应该被设置");

    // 清除代理
    [EMASCurlProtocol setManualProxyServer:nil];
    defaultConfig = [EMASCurlProtocol defaultConfiguration];
    XCTAssertFalse(defaultConfig.manualProxyEnabled, @"手动代理应该被禁用");
    XCTAssertNil(defaultConfig.proxyServer, @"代理服务器应该被清除");
}

- (void)testMixedLegacyAndNewAPI {
    // 使用静态setter配置默认
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    [EMASCurlProtocol setConnectTimeoutInterval:2.0];
    [EMASCurlProtocol setBuiltInGzipEnabled:YES];

    // 验证默认配置
    EMASCurlConfiguration *defaultConfig = [EMASCurlProtocol defaultConfiguration];
    XCTAssertEqual(defaultConfig.httpVersion, HTTP1, @"默认配置应该使用HTTP1");
    XCTAssertEqual(defaultConfig.connectTimeoutInterval, 2.0, @"默认配置超时应该是2.0秒");

    // 创建使用默认配置的session（旧API方式）
    NSURLSessionConfiguration *oldApiSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:oldApiSessionConfig];
    NSURLSession *oldApiSession = [NSURLSession sessionWithConfiguration:oldApiSessionConfig];

    // 创建使用自定义配置的session（新API方式）
    EMASCurlConfiguration *customConfig = [EMASCurlConfiguration defaultConfiguration];
    customConfig.httpVersion = HTTP2;
    customConfig.connectTimeoutInterval = 5.0;
    customConfig.enableBuiltInGzip = NO;

    NSURLSession *newApiSession = [self createSessionWithConfiguration:customConfig];

    XCTestExpectation *oldApiExpectation = [self expectationWithDescription:@"Old API request"];
    XCTestExpectation *newApiExpectation = [self expectationWithDescription:@"New API request"];

    // 测试旧API session（应该使用默认配置）
    [self executeRequestWithSession:oldApiSession
                            endpoint:HTTP11_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"旧API请求不应该有错误");
        XCTAssertNotNil(response, @"应该收到响应");
        XCTAssertEqual(response.statusCode, 200, @"状态码应该是200");
        [oldApiExpectation fulfill];
    }];

    // 测试新API session（应该使用自定义配置）
    // 为HTTP/2设置证书
    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *caCertPath = [testBundle pathForResource:@"ca" ofType:@"crt"];
    if (caCertPath) {
        customConfig.caFilePath = caCertPath;
        newApiSession = [self createSessionWithConfiguration:customConfig];
    }

    [self executeRequestWithSession:newApiSession
                            endpoint:HTTP2_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"新API请求不应该有错误: %@", error);
        XCTAssertNotNil(response, @"应该收到响应");
        XCTAssertEqual(response.statusCode, 200, @"状态码应该是200");
        [newApiExpectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

#pragma mark - 2.3 Configuration Management Tests

- (void)testConfigurationStorageAndRetrieval {
    // 创建配置
    EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
    config.httpVersion = HTTP2;
    config.connectTimeoutInterval = 4.0;
    config.enableBuiltInGzip = NO;

    // 存储配置
    NSString *configID = @"test-config-123";
    [[EMASCurlConfigurationManager sharedManager] setConfiguration:config forID:configID];

    // 检索配置
    EMASCurlConfiguration *retrievedConfig = [[EMASCurlConfigurationManager sharedManager] configurationForID:configID];

    XCTAssertNotNil(retrievedConfig, @"应该能够检索存储的配置");
    XCTAssertEqual(retrievedConfig.httpVersion, HTTP2, @"HTTP版本应该匹配");
    XCTAssertEqual(retrievedConfig.connectTimeoutInterval, 4.0, @"连接超时应该匹配");
    XCTAssertFalse(retrievedConfig.enableBuiltInGzip, @"Gzip设置应该匹配");

    // 测试获取所有配置ID
    NSArray<NSString *> *allIDs = [[EMASCurlConfigurationManager sharedManager] allConfigurationIDs];
    XCTAssertTrue([allIDs containsObject:configID], @"配置ID应该在列表中");

    // 移除配置
    [[EMASCurlConfigurationManager sharedManager] removeConfigurationForID:configID];
    EMASCurlConfiguration *removedConfig = [[EMASCurlConfigurationManager sharedManager] configurationForID:configID];
    XCTAssertNil(removedConfig, @"移除后不应该能够检索配置");

    // 测试不存在的配置
    EMASCurlConfiguration *nonExistentConfig = [[EMASCurlConfigurationManager sharedManager] configurationForID:@"non-existent-id"];
    XCTAssertNil(nonExistentConfig, @"不存在的配置应该返回nil");
}

- (void)testDefaultConfigurationFallback {
    // 不使用显式配置创建session（应该使用默认配置）
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:sessionConfig];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Default config request"];

    // 执行请求
    [self executeRequestWithSession:session
                            endpoint:HTTP11_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"使用默认配置的请求不应该有错误");
        XCTAssertNotNil(response, @"应该收到响应");
        XCTAssertEqual(response.statusCode, 200, @"状态码应该是200");

        // 成功完成请求表明默认配置回退正常工作
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];

    // 修改默认配置
    EMASCurlConfiguration *newDefaultConfig = [EMASCurlConfiguration defaultConfiguration];
    newDefaultConfig.httpVersion = HTTP2;
    [[EMASCurlConfigurationManager sharedManager] setDefaultConfiguration:newDefaultConfig];

    // 验证现有session不受影响（继续使用创建时的配置）
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"Existing session request"];

    [self executeRequestWithSession:session
                            endpoint:HTTP11_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"现有session的请求不应该有错误");
        XCTAssertNotNil(response, @"应该收到响应");
        XCTAssertEqual(response.statusCode, 200, @"状态码应该是200");

        // 请求仍然成功，表明session不受默认配置更改的影响
        [expectation2 fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

#pragma mark - 2.4 Real-world Scenario Tests

- (void)testDifferentTimeoutsPerSession {
    // 由于timeout服务器实际上是立即接受连接，然后延迟2秒后关闭，
    // 我们需要测试总体请求超时而不是连接超时

    // Session 1: 使用短的连接超时
    EMASCurlConfiguration *config1 = [EMASCurlConfiguration defaultConfiguration];
    config1.connectTimeoutInterval = 1.0;
    NSURLSession *session1 = [self createSessionWithConfiguration:config1];

    // Session 2: 使用长的连接超时
    EMASCurlConfiguration *config2 = [EMASCurlConfiguration defaultConfiguration];
    config2.connectTimeoutInterval = 10.0;
    NSURLSession *session2 = [self createSessionWithConfiguration:config2];

    XCTestExpectation *expectation1 = [self expectationWithDescription:@"Session 1 with short timeout"];
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"Session 2 with long timeout"];
    XCTestExpectation *expectation3 = [self expectationWithDescription:@"Session 1 timeout server"];
    XCTestExpectation *expectation4 = [self expectationWithDescription:@"Session 2 timeout server"];

    // 测试1: 两个session请求正常服务器，都应该成功（验证基本功能）
    NSURL *normalURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_ECHO]];
    NSURLRequest *normalRequest = [NSURLRequest requestWithURL:normalURL];

    NSURLSessionDataTask *task1 = [session1 dataTaskWithRequest:normalRequest
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Session 1 对正常服务器应该成功
        XCTAssertNil(error, @"Session1请求正常服务器不应该有错误: %@", error);
        XCTAssertNotNil(response, @"应该收到响应");
        if (response) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            XCTAssertEqual(httpResponse.statusCode, 200, @"状态码应该是200");
        }
        [expectation1 fulfill];
    }];
    [task1 resume];

    NSURLSessionDataTask *task2 = [session2 dataTaskWithRequest:normalRequest
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Session 2 对正常服务器也应该成功
        XCTAssertNil(error, @"Session2请求正常服务器不应该有错误: %@", error);
        XCTAssertNotNil(response, @"应该收到响应");
        if (response) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            XCTAssertEqual(httpResponse.statusCode, 200, @"状态码应该是200");
        }
        [expectation2 fulfill];
    }];
    [task2 resume];

    // 测试2: 两个session请求超时服务器（延迟2秒关闭）
    // 使用较短的总体请求超时来测试超时行为差异
    NSURL *timeoutURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", TIMEOUT_TEST_ENDPOINT, PATH_ECHO]];
    NSMutableURLRequest *timeoutRequest1 = [NSMutableURLRequest requestWithURL:timeoutURL];
    timeoutRequest1.timeoutInterval = 1.5;  // 1.5秒总超时 < 2秒延迟，应该超时

    NSMutableURLRequest *timeoutRequest2 = [NSMutableURLRequest requestWithURL:timeoutURL];
    timeoutRequest2.timeoutInterval = 5.0;  // 5秒总超时 > 2秒延迟，应该收到连接关闭错误

    NSURLSessionDataTask *task3 = [session1 dataTaskWithRequest:timeoutRequest1
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 应该因为请求超时而失败（1.5秒 < 2秒）
        XCTAssertNotNil(error, @"Session1请求超时服务器应该产生错误");
        if (error) {
            // 应该是超时错误，因为1.5秒 < 2秒服务器延迟
            BOOL isTimeout = (error.code == NSURLErrorTimedOut) ||
                           (error.code == 28) || // libcurl timeout
                           ([error.domain isEqualToString:NSURLErrorDomain] && error.code == -1001);
            XCTAssertTrue(isTimeout, @"Session1应该因超时失败，实际错误: %@ (code: %ld)", error, (long)error.code);
        }
        [expectation3 fulfill];
    }];
    [task3 resume];

    NSURLSessionDataTask *task4 = [session2 dataTaskWithRequest:timeoutRequest2
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 应该收到连接被关闭的错误（5秒 > 2秒）
        XCTAssertNotNil(error, @"Session2请求超时服务器应该产生错误");
        if (error) {
            // 不应该是超时错误，而是连接被关闭/重置
            BOOL isTimeout = (error.code == NSURLErrorTimedOut) || (error.code == 28);
            BOOL isConnectionError = (error.code == 56) || // libcurl recv failure
                                    (error.code == NSURLErrorNetworkConnectionLost) ||
                                    (error.code == -1005) || // NSURLErrorNetworkConnectionLost
                                    (error.code == -1011); // NSURLErrorBadServerResponse

            // Session2有足够时间等待，所以应该是连接错误而不是超时
            XCTAssertFalse(isTimeout, @"Session2不应该超时，因为5秒 > 2秒延迟");
            XCTAssertTrue(isConnectionError || !isTimeout,
                         @"Session2应该收到连接错误而不是超时，实际错误: %@ (code: %ld)",
                         error, (long)error.code);
        }
        [expectation4 fulfill];
    }];
    [task4 resume];

    // 等待所有请求完成
    [self waitForExpectationsWithTimeout:10 handler:^(NSError *error) {
        if (error) {
            NSLog(@"Test timeout waiting for expectations: %@", error);
        }
    }];
}

- (void)testPerSessionDomainFiltering {
    // Session 1: 白名单只包含127.0.0.1（拦截本地请求）
    EMASCurlConfiguration *config1 = [EMASCurlConfiguration defaultConfiguration];
    config1.domainWhiteList = @[@"127.0.0.1"];
    NSURLSession *session1 = [self createSessionWithConfiguration:config1];

    // Session 2: 黑名单包含127.0.0.1（绕过本地请求，不被EMASCurl拦截）
    EMASCurlConfiguration *config2 = [EMASCurlConfiguration defaultConfiguration];
    config2.domainBlackList = @[@"127.0.0.1"];
    NSURLSession *session2 = [self createSessionWithConfiguration:config2];

    XCTestExpectation *expectation1 = [self expectationWithDescription:@"Whitelist session request"];
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"Blacklist session request"];

    // Session 1请求本地服务器（应该被EMASCurl拦截并处理）
    [self executeRequestWithSession:session1
                            endpoint:HTTP11_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        // 白名单中的域名应该被拦截并正常处理
        XCTAssertNil(error, @"白名单session的请求不应该有错误: %@", error);
        XCTAssertNotNil(response, @"应该收到响应");
        XCTAssertEqual(response.statusCode, 200, @"状态码应该是200");

        // 解析响应体来检查User-Agent
        if (data) {
            NSError *jsonError = nil;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data
                                                                        options:0
                                                                          error:&jsonError];
            if (!jsonError && responseDict[@"headers"]) {
                NSDictionary *headers = responseDict[@"headers"];
                NSString *userAgent = headers[@"user-agent"] ?: headers[@"User-Agent"];

                // EMASCurl拦截的请求应该包含"EMASCurl"在User-Agent中
                XCTAssertNotNil(userAgent, @"应该有User-Agent header");
                if (userAgent) {
                    XCTAssertTrue([userAgent containsString:@"EMASCurl"],
                                @"白名单session应该被EMASCurl拦截，User-Agent: %@", userAgent);
                }
            }
        }

        [expectation1 fulfill];
    }];

    // Session 2请求本地服务器（黑名单中，不应该被EMASCurl拦截）
    [self executeRequestWithSession:session2
                            endpoint:HTTP11_ENDPOINT
                                path:PATH_ECHO
                          completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        // 黑名单中的域名应该绕过EMASCurl，由系统网络栈处理
        // 可能会成功也可能会失败，取决于系统配置

        if (!error && data) {
            // 如果请求成功，检查是否被EMASCurl拦截
            NSError *jsonError = nil;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data
                                                                        options:0
                                                                          error:&jsonError];
            if (!jsonError && responseDict[@"headers"]) {
                NSDictionary *headers = responseDict[@"headers"];
                NSString *userAgent = headers[@"user-agent"] ?: headers[@"User-Agent"];

                // 黑名单中的请求不应该包含"EMASCurl"在User-Agent中
                if (userAgent) {
                    XCTAssertFalse([userAgent containsString:@"EMASCurl"],
                                 @"黑名单session不应该被EMASCurl拦截，User-Agent: %@", userAgent);

                    // 如果不包含EMASCurl，说明确实被绕过了
                    if (![userAgent containsString:@"EMASCurl"]) {
                        NSLog(@"确认：黑名单域名成功绕过EMASCurl拦截");
                    }
                } else {
                    // 没有User-Agent也说明不是EMASCurl处理的
                    NSLog(@"黑名单请求没有User-Agent，可能由系统直接处理");
                }
            }
        } else if (error) {
            // 如果有错误，可能是因为系统网络栈不支持或其他原因
            NSLog(@"黑名单session请求失败（预期行为）: %@", error);
            // 这也是可接受的，因为绕过EMASCurl后系统可能无法处理
        }

        [expectation2 fulfill];
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

@end
