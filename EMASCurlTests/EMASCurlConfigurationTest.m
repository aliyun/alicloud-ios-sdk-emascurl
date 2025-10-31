//
//  EMASCurlConfigurationTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2025/01/02.
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlConfigurationManager.h"

@interface EMASCurlConfigurationTest : XCTestCase
@property (nonatomic, strong) EMASCurlConfiguration *config;
@end

@implementation EMASCurlConfigurationTest

- (void)setUp {
    [super setUp];
    self.config = [EMASCurlConfiguration defaultConfiguration];
}

- (void)tearDown {
    self.config = nil;
    [super tearDown];
}

#pragma mark - Core Tests

- (void)testDefaultConfiguration {
    // 测试默认配置值
    EMASCurlConfiguration *defaultConfig = [EMASCurlConfiguration defaultConfiguration];

    // 验证核心网络设置
    XCTAssertEqual(defaultConfig.httpVersion, HTTP1, @"默认HTTP版本应该是HTTP1");
    XCTAssertEqual(defaultConfig.connectTimeoutInterval, 2.5, @"默认连接超时应该是2.5秒");
    XCTAssertTrue(defaultConfig.enableBuiltInGzip, @"默认应该启用gzip");
    XCTAssertTrue(defaultConfig.enableBuiltInRedirection, @"默认应该启用重定向");

    // 验证安全设置
    XCTAssertTrue(defaultConfig.certificateValidationEnabled, @"默认应该启用证书验证");
    XCTAssertTrue(defaultConfig.domainNameVerificationEnabled, @"默认应该启用域名验证");

    // 验证缓存设置
    XCTAssertTrue(defaultConfig.cacheEnabled, @"默认应该启用缓存");

    // 验证代理设置
    XCTAssertNil(defaultConfig.proxyServer, @"默认代理服务器应该为nil");

    // 验证DNS设置
    XCTAssertNil(defaultConfig.dnsResolver, @"默认DNS解析器应该为nil");

    // 验证域名过滤
    XCTAssertNil(defaultConfig.domainWhiteList, @"默认域名白名单应该为nil");
    XCTAssertNil(defaultConfig.domainBlackList, @"默认域名黑名单应该为nil");
}

- (void)testConfigurationCopy {
    // 创建自定义配置
    EMASCurlConfiguration *original = [EMASCurlConfiguration defaultConfiguration];
    original.httpVersion = HTTP2;
    original.connectTimeoutInterval = 5.0;
    original.enableBuiltInGzip = NO;
    original.enableBuiltInRedirection = NO;
    original.certificateValidationEnabled = NO;
    original.domainNameVerificationEnabled = NO;
    original.cacheEnabled = NO;
    original.proxyServer = @"http://proxy.test.com:8080";
    original.domainWhiteList = @[@"api.example.com", @"cdn.example.com"];
    original.domainBlackList = @[@"tracking.com"];
    original.caFilePath = @"/path/to/ca.pem";
    original.publicKeyPinningKeyPath = @"/path/to/public.key";

    // 复制配置
    EMASCurlConfiguration *copy = [original copy];

    // 验证所有属性都被正确复制
    XCTAssertEqual(copy.httpVersion, original.httpVersion, @"HTTP版本应该相同");
    XCTAssertEqual(copy.connectTimeoutInterval, original.connectTimeoutInterval, @"连接超时应该相同");
    XCTAssertEqual(copy.enableBuiltInGzip, original.enableBuiltInGzip, @"gzip设置应该相同");
    XCTAssertEqual(copy.enableBuiltInRedirection, original.enableBuiltInRedirection, @"重定向设置应该相同");
    XCTAssertEqual(copy.certificateValidationEnabled, original.certificateValidationEnabled, @"证书验证设置应该相同");
    XCTAssertEqual(copy.domainNameVerificationEnabled, original.domainNameVerificationEnabled, @"域名验证设置应该相同");
    XCTAssertEqual(copy.cacheEnabled, original.cacheEnabled, @"缓存设置应该相同");
    XCTAssertEqualObjects(copy.proxyServer, original.proxyServer, @"代理服务器应该相同");
    XCTAssertEqualObjects(copy.domainWhiteList, original.domainWhiteList, @"域名白名单应该相同");
    XCTAssertEqualObjects(copy.domainBlackList, original.domainBlackList, @"域名黑名单应该相同");
    XCTAssertEqualObjects(copy.caFilePath, original.caFilePath, @"CA文件路径应该相同");
    XCTAssertEqualObjects(copy.publicKeyPinningKeyPath, original.publicKeyPinningKeyPath, @"公钥路径应该相同");

    // 验证是深拷贝 - 修改原始配置不影响副本
    original.httpVersion = HTTP1;
    original.connectTimeoutInterval = 1.0;
    original.enableBuiltInGzip = YES;
    original.proxyServer = @"http://another.proxy.com:3128";
    [original.domainWhiteList arrayByAddingObject:@"new.domain.com"];

    // 验证副本未被修改
    XCTAssertEqual(copy.httpVersion, HTTP2, @"副本的HTTP版本不应该改变");
    XCTAssertEqual(copy.connectTimeoutInterval, 5.0, @"副本的连接超时不应该改变");
    XCTAssertFalse(copy.enableBuiltInGzip, @"副本的gzip设置不应该改变");
    XCTAssertEqualObjects(copy.proxyServer, @"http://proxy.test.com:8080", @"副本的代理服务器不应该改变");
    XCTAssertEqual(copy.domainWhiteList.count, 2, @"副本的域名白名单不应该改变");
}

- (void)testConfigurationHeaderRemoval {
    // 测试X-EMASCurl-Config-ID header是否被正确移除，不发送给服务器

    // 创建自定义配置
    EMASCurlConfiguration *customConfig = [EMASCurlConfiguration defaultConfiguration];
    customConfig.httpVersion = HTTP2;
    customConfig.connectTimeoutInterval = 3.0;

    // 创建session配置并安装EMASCurl
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:sessionConfig withConfiguration:customConfig];

    // 验证HTTPAdditionalHeaders包含X-EMASCurl-Config-ID
    NSDictionary *headers = sessionConfig.HTTPAdditionalHeaders;
    XCTAssertNotNil(headers, @"Session应该有HTTPAdditionalHeaders");
    XCTAssertNotNil(headers[@"X-EMASCurl-Config-ID"], @"应该包含X-EMASCurl-Config-ID header");

    NSString *configID = headers[@"X-EMASCurl-Config-ID"];
    XCTAssertTrue([configID length] > 0, @"配置ID不应该为空");

    // 创建session
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];

    // 创建期望
    XCTestExpectation *expectation = [self expectationWithDescription:@"Request completion"];

    // 发送请求到echo端点，该端点会返回收到的所有headers
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9080/echo"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            // 解析响应数据
            NSError *jsonError = nil;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data
                                                                        options:0
                                                                          error:&jsonError];

            if (!jsonError && responseDict[@"headers"]) {
                NSDictionary *receivedHeaders = responseDict[@"headers"];

                // 验证X-EMASCurl-Config-ID不在服务器收到的headers中
                XCTAssertNil(receivedHeaders[@"X-EMASCurl-Config-ID"],
                           @"X-EMASCurl-Config-ID不应该被发送到服务器");
                XCTAssertNil(receivedHeaders[@"x-emascurl-config-id"],
                           @"x-emascurl-config-id(小写)不应该被发送到服务器");

                // 验证EMASCurl的User-Agent存在，确认请求被EMASCurl处理
                NSString *userAgent = receivedHeaders[@"user-agent"] ?: receivedHeaders[@"User-Agent"];
                if (userAgent) {
                    XCTAssertTrue([userAgent containsString:@"EMASCurl"],
                                @"请求应该被EMASCurl处理，User-Agent: %@", userAgent);
                }
            } else {
                XCTFail(@"无法解析响应数据或缺少headers字段");
            }
        } else if (error) {
            // 如果测试服务器未运行，跳过断言
            NSLog(@"请求失败（可能是测试服务器未运行）: %@", error);
        }

        [expectation fulfill];
    }];

    [task resume];

    // 等待请求完成
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

@end
