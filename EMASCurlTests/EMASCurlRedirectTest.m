//
//  EMASCurlRedirectTest.m
//
//  EMASCurl
//
//  @author Created by Claude Code on 2025/11/30
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

@interface EMASCurlRedirectTest : XCTestCase

@property (nonatomic, strong) NSURLSession *session;

@end

@implementation EMASCurlRedirectTest

- (void)setUp {
    [super setUp];

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;
    curlConfig.enableBuiltInRedirection = YES;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)tearDown {
    [self.session invalidateAndCancel];
    self.session = nil;
    [super tearDown];
}

#pragma mark - Basic Redirect Tests

- (void)testSingleRedirect302 {
    XCTestExpectation *expectation = [self expectationWithDescription:@"302 redirect"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_REDIRECT]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed: %@", error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should follow redirect to final 200 response");

        // 验证最终响应是 /echo 的内容
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertEqualObjects(json[@"method"], @"GET", @"Should be GET after redirect");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];
}

- (void)testSingleRedirect301 {
    XCTestExpectation *expectation = [self expectationWithDescription:@"301 redirect"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_REDIRECT_301]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed: %@", error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should follow 301 redirect");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];
}

- (void)testSingleRedirect307 {
    XCTestExpectation *expectation = [self expectationWithDescription:@"307 redirect"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_REDIRECT_307]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed: %@", error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should follow 307 redirect");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];
}

- (void)testMultipleRedirectChain {
    XCTestExpectation *expectation = [self expectationWithDescription:@"redirect chain"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_REDIRECT_CHAIN]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed: %@", error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should follow redirect chain to final response");

        // 验证到达了 /echo
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertEqualObjects(json[@"method"], @"GET");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];
}

#pragma mark - Redirection Disabled Tests

- (void)testRedirectionDisabledStillFollowsViaDelegate {
    // 当 enableBuiltInRedirection = NO 时，libcurl 不自动跟随重定向
    // 但 EMASCurlProtocol 会调用 wasRedirectedToRequest: 通知 NSURLSession
    // NSURLSession 默认行为是跟随重定向，所以最终仍会到达目标页面
    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;
    curlConfig.enableBuiltInRedirection = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    NSURLSession *noRedirectSession = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    XCTestExpectation *expectation = [self expectationWithDescription:@"redirect via delegate"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_REDIRECT]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [noRedirectSession dataTaskWithRequest:request
                                                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed: %@", error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        // NSURLSession 默认跟随重定向，最终返回 200
        XCTAssertEqual(httpResponse.statusCode, 200, @"NSURLSession follows redirect via delegate callback");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];

    [noRedirectSession invalidateAndCancel];
}

- (void)testBuiltInRedirectionEnabled301 {
    // 验证 enableBuiltInRedirection = YES (默认) 时 301 重定向正常工作
    XCTestExpectation *expectation = [self expectationWithDescription:@"builtin redirect 301"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_REDIRECT_301]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should follow 301 redirect to final 200");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];
}

#pragma mark - 307 POST Method Preservation Test

- (void)testRedirect307FollowsSuccessfully {
    // 测试 307 重定向能够成功跟随
    // 注意：libcurl 默认不设置 CURLOPT_POSTREDIR，307 重定向后方法可能变为 GET
    XCTestExpectation *expectation = [self expectationWithDescription:@"307 redirect"];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_REDIRECT_307]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed: %@", error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should follow 307 redirect");

        // 验证响应数据有效
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);
        XCTAssertNotNil(json[@"method"], @"Response should contain method");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];
}

#pragma mark - Cookie Preservation Test

- (void)testRedirectPreservesCookies {
    // 创建带 cookie 存储的 session
    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;
    curlConfig.enableBuiltInRedirection = YES;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldSetCookies = YES;
    config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
    config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    NSURLSession *cookieSession = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    XCTestExpectation *expectation = [self expectationWithDescription:@"redirect with cookies"];

    // 访问设置 cookie 并重定向到验证页面的 URL
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_REDIRECT_SET_COOKIE]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [cookieSession dataTaskWithRequest:request
                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed: %@", error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Should reach /cookie/verify");

        [expectation fulfill];
    }];

    [task resume];
    [self waitForExpectations:@[expectation] timeout:10.0];

    [cookieSession invalidateAndCancel];
}

@end
