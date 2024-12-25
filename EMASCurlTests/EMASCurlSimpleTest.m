//
//  EMASCurlSimpleTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2024/12/16.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

static NSURLSession *session;

@interface EMASCurlSimpleTestBase : XCTestCase

@end

@implementation EMASCurlSimpleTestBase

#pragma mark - Helper Methods

- (void)executeRequest:(NSString *)endpoint
                  path:(NSString *)path
                method:(NSString *)method
                  body:(NSDictionary *)body
               headers:(NSDictionary *)headers
       validationBlock:(void (^)(NSData *data, NSHTTPURLResponse *response))validationBlock {

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;

    // Add body if provided
    if (body) {
        NSError *jsonError;
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Failed to serialize request body: %@", jsonError);
        request.HTTPBody = bodyData;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }

    // Add custom headers
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        // Common response validation
        [self validateCommonResponse:httpResponse];

        // Custom validation if provided
        if (validationBlock) {
            validationBlock(data, httpResponse);
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)validateCommonResponse:(NSHTTPURLResponse *)response {
    XCTAssertEqual(response.statusCode, 200, @"Expected status code 200, got %ld", (long)response.statusCode);
}

- (void)validateEchoResponse:(NSData *)data expectedMethod:(NSString *)method {
    NSError *jsonError;
    NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    XCTAssertNil(jsonError, @"Failed to parse response JSON: %@", jsonError);
    XCTAssertEqualObjects(responseData[@"method"], method, @"Expected %@ method in response", method);
}

#pragma mark - Test Methods

- (void)headRequest:(NSString *)endpoint {
    [self executeRequest:endpoint
                    path:PATH_ECHO
                  method:@"HEAD"
                    body:nil
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        XCTAssertEqual(data.length, 0, @"HEAD request should not return body data");
    }];
}

- (void)deleteRequest:(NSString *)endpoint {
    [self executeRequest:endpoint
                    path:PATH_ECHO
                  method:@"DELETE"
                    body:nil
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        [self validateEchoResponse:data expectedMethod:@"DELETE"];
    }];
}

- (void)putRequest:(NSString *)endpoint {
    NSDictionary *requestBody = @{@"test": @"data"};
    [self executeRequest:endpoint
                    path:PATH_ECHO
                  method:@"PUT"
                    body:requestBody
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        [self validateEchoResponse:data expectedMethod:@"PUT"];

        NSError *jsonError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *bodyContent = responseData[@"body"];
        XCTAssertNotNil(bodyContent, @"Expected body content in response");
        XCTAssertTrue([bodyContent containsString:@"test"], @"Expected request body to be echoed back");
    }];
}

- (void)postRequest:(NSString *)endpoint {
    NSDictionary *requestBody = @{
        @"name": @"test_user",
        @"age": @25,
        @"email": @"test@example.com"
    };

    [self executeRequest:endpoint
                    path:PATH_ECHO
                  method:@"POST"
                    body:requestBody
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        [self validateEchoResponse:data expectedMethod:@"POST"];

        NSError *jsonError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *bodyContent = responseData[@"body"];
        XCTAssertNotNil(bodyContent, @"Expected body content in response");
        XCTAssertTrue([bodyContent containsString:@"test_user"], @"Expected name in echoed body");
        XCTAssertTrue([bodyContent containsString:@"test@example.com"], @"Expected email in echoed body");
    }];
}

- (void)optionsRequest:(NSString *)endpoint {
    NSDictionary *headers = @{
        @"Access-Control-Request-Headers": @"*",
        @"Access-Control-Request-Method": @"PUT, DELETE",
        @"Origin": @"example.com"
    };

    [self executeRequest:endpoint
                    path:PATH_ECHO
                  method:@"OPTIONS"
                    body:nil
                 headers:headers
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        [self validateEchoResponse:data expectedMethod:@"OPTIONS"];

        NSDictionary *responseHeaders = response.allHeaderFields;
        XCTAssertNotNil(responseHeaders[@"access-control-allow-origin"], @"Expected CORS headers in response");
        XCTAssertNotNil(responseHeaders[@"access-control-allow-methods"], @"Expected allowed methods in response");
    }];
}

- (void)getRequest:(NSString *)endpoint {
    [self executeRequest:endpoint
                    path:PATH_ECHO
                  method:@"GET"
                    body:nil
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        [self validateEchoResponse:data expectedMethod:@"GET"];
    }];
}

- (void)getRedirectRequest:(NSString *)endpoint {
    [self executeRequest:endpoint
                    path:PATH_REDIRECT
                  method:@"GET"
                    body:nil
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        [self validateEchoResponse:data expectedMethod:@"GET"];
    }];
}

- (void)getRedirectChainRequest:(NSString *)endpoint {
    [self executeRequest:endpoint
                    path:PATH_REDIRECT_CHAIN
                  method:@"GET"
                    body:nil
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        [self validateEchoResponse:data expectedMethod:@"GET"];
    }];
}

- (void)getGzipResponse:(NSString *)endpoint {
    [self executeRequest:endpoint
                    path:PATH_GZIP_RESPONSE
                  method:@"GET"
                    body:nil
                 headers:nil
         validationBlock:^(NSData *data, NSHTTPURLResponse *response) {
        NSDictionary *responseHeaders = response.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"content-encoding"], @"gzip", @"Expected gzip content encoding");
        XCTAssertEqualObjects(responseHeaders[@"content-type"], @"application/json", @"Expected JSON content type");

        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Failed to parse JSON response: %@", jsonError);
        XCTAssertEqualObjects(jsonResponse[@"message"], @"This is a gzipped response", @"Unexpected response message");
    }];
}

@end

@interface EMASCurlSimpleTestHttp11 : EMASCurlSimpleTestBase

@end

@implementation EMASCurlSimpleTestHttp11

+ (void)setUp {
    [EMASCurlProtocol setDebugLogEnabled:YES];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;  // Enable redirect following
    config.HTTPShouldSetCookies = YES;
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testHeadRequest {
    [self headRequest:HTTP11_ENDPOINT];
}

- (void)testDeleteRequest {
    [self deleteRequest:HTTP11_ENDPOINT];
}

- (void)testPutRequest {
    [self putRequest:HTTP11_ENDPOINT];
}

- (void)testPostRequest {
    [self postRequest:HTTP11_ENDPOINT];
}

- (void)testOptionsRequest {
    [self optionsRequest:HTTP11_ENDPOINT];
}

- (void)testGetRequest {
    [self getRequest:HTTP11_ENDPOINT];
}

- (void)testGetRedirectRequest {
    [self getRedirectRequest:HTTP11_ENDPOINT];
}

- (void)testGetRedirectChainRequest {
    [self getRedirectChainRequest:HTTP11_ENDPOINT];
}

- (void)testGetGzipResponse {
    [self getGzipResponse:HTTP11_ENDPOINT];
}

@end

@interface EMASCurlSimpleTestHttp2 : EMASCurlSimpleTestBase
@end

@implementation EMASCurlSimpleTestHttp2

+ (void)setUp {
    [EMASCurlProtocol setDebugLogEnabled:YES];

    [EMASCurlProtocol setHTTPVersion:HTTP2];

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *certPath = [testBundle pathForResource:@"ca" ofType:@"crt"];
    XCTAssertNotNil(certPath, @"Certificate file not found in test bundle.");
    [EMASCurlProtocol setSelfSignedCAFilePath:certPath];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;  // Enable redirect following
    config.HTTPShouldSetCookies = YES;
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testHeadRequest {
    [self headRequest:HTTP2_ENDPOINT];
}

- (void)testDeleteRequest {
    [self deleteRequest:HTTP2_ENDPOINT];
}

- (void)testPutRequest {
    [self putRequest:HTTP2_ENDPOINT];
}

- (void)testPostRequest {
    [self postRequest:HTTP2_ENDPOINT];
}

- (void)testOptionsRequest {
    [self optionsRequest:HTTP2_ENDPOINT];
}

- (void)testGetRequest {
    [self getRequest:HTTP2_ENDPOINT];
}

- (void)testGetRedirectRequest {
    [self getRedirectRequest:HTTP2_ENDPOINT];
}

- (void)testGetRedirectChainRequest {
    [self getRedirectChainRequest:HTTP2_ENDPOINT];
}

- (void)testGetGzipResponse {
    [self getGzipResponse:HTTP2_ENDPOINT];
}

@end
