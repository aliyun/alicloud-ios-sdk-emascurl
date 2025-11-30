//
//  EMASCurlSSLValidationTest.m
//
//  EMASCurl
//
//  @author Created by Claude Code on 2025/11/30
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

@interface EMASCurlSSLValidationTest : XCTestCase

@end

@implementation EMASCurlSSLValidationTest

#pragma mark - SSL Validation Disabled Tests

- (void)testCertificateValidationDisabledShouldSucceed {
    // 禁用证书验证后访问自签名 HTTPS 应成功
    XCTestExpectation *expectation = [self expectationWithDescription:@"SSL disabled should succeed"];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.certificateValidationEnabled = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP2_ENDPOINT, PATH_ECHO]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request should succeed with SSL validation disabled: %@", error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should receive 200 OK");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];

    [session invalidateAndCancel];
}

- (void)testBothValidationsDisabled {
    // 同时禁用证书验证和域名验证
    XCTestExpectation *expectation = [self expectationWithDescription:@"both validations disabled"];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.certificateValidationEnabled = NO;
    curlConfig.domainNameVerificationEnabled = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP2_ENDPOINT, PATH_ECHO]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request should succeed: %@", error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];

    [session invalidateAndCancel];
}

#pragma mark - Invalid CA Path Test

- (void)testInvalidCAFilePathShouldFail {
    // 无效的 CA 文件路径应导致 SSL 失败
    XCTestExpectation *expectation = [self expectationWithDescription:@"invalid CA path should fail"];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.caFilePath = @"/nonexistent/path/to/ca.crt";
    curlConfig.certificateValidationEnabled = YES;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP2_ENDPOINT, PATH_ECHO]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 应该收到错误（无效 CA 路径或 SSL 验证失败）
        XCTAssertNotNil(error, @"Should receive an error with invalid CA path");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];

    [session invalidateAndCancel];
}

#pragma mark - HTTP Not Affected by SSL Config

- (void)testDefaultConfigurationWithHTTPShouldWork {
    // 验证 HTTP 请求不受 SSL 配置影响
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP should work regardless of SSL config"];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;
    // 即使开启 SSL 验证，HTTP 请求也应正常工作

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_ECHO]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"HTTP request should succeed: %@", error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];

    [session invalidateAndCancel];
}

#pragma mark - Domain Verification Tests

- (void)testDomainVerificationDisabledWithoutCA {
    // 禁用域名验证和证书验证一起测试
    XCTestExpectation *expectation = [self expectationWithDescription:@"domain verification disabled"];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.certificateValidationEnabled = NO;
    curlConfig.domainNameVerificationEnabled = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    // 使用 IP 地址访问
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP2_ENDPOINT, PATH_ECHO]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request should succeed with all SSL validation disabled: %@", error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];

    [session invalidateAndCancel];
}

@end
