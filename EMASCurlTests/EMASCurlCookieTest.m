//
//  EMASCurlCookieTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2025/2/3.
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

@interface EMASCurlCookieTest : XCTestCase

@property (nonatomic, strong) NSURLSession *session;

@end

@implementation EMASCurlCookieTest

- (void)setUp {
    [super setUp];

    [EMASCurlProtocol setDebugLogEnabled:YES];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    _session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)tearDown {
    // 清理所有 cookies
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray<NSHTTPCookie *> *cookies = [storage cookies];
    for (NSHTTPCookie *cookie in cookies) {
        [storage deleteCookie:cookie];
    }
    [super tearDown];
}

- (void)testCookiePersistence {
    // 1. 首先获取 cookie
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSString *urlString = [NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_COOKIE_SET];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    __block NSString *setCookieHeader = nil;
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");

        NSDictionary *headers = [httpResponse allHeaderFields];
        setCookieHeader = headers[@"Set-Cookie"];
        XCTAssertNotNil(setCookieHeader, @"No Set-Cookie header received");

        dispatch_semaphore_signal(semaphore);
    }] resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    // 2. 验证 cookie 是否被正确设置
    NSString *verifyUrlString = [NSString stringWithFormat:@"%@%@", HTTP11_ENDPOINT, PATH_COOKIE_VERIFY];
    NSURL *verifyUrl = [NSURL URLWithString:verifyUrlString];
    NSMutableURLRequest *verifyRequest = [NSMutableURLRequest requestWithURL:verifyUrl];

    semaphore = dispatch_semaphore_create(0);
    __block BOOL cookieValid = NO;

    [[self.session dataTaskWithRequest:verifyRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        XCTAssertNil(error, @"Verify request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received for verify request");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code for verify request");

        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            cookieValid = [json[@"status"] isEqualToString:@"valid_cookie"];
        }

        dispatch_semaphore_signal(semaphore);
    }] resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    XCTAssertTrue(cookieValid, @"Cookie validation failed");
}

@end
