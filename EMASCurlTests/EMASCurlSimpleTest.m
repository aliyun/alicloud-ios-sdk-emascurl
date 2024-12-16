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

- (void)headRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_ECHO]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"HEAD";

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected status code 200, got %ld", (long)httpResponse.statusCode);

        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"x-echo-server"], @"FastAPI", @"Expected FastAPI echo server header");

        XCTAssertEqual(data.length, 0, @"HEAD request should not return body data");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)deleteRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_ECHO]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"DELETE";

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected status code 200, got %ld", (long)httpResponse.statusCode);

        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"x-echo-server"], @"FastAPI", @"Expected FastAPI echo server header");

        NSError *jsonError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Failed to parse response JSON: %@", jsonError);
        XCTAssertEqualObjects(responseData[@"method"], @"DELETE", @"Expected DELETE method in response");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)putRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_ECHO]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"PUT";

    // Add request body
    NSDictionary *requestBody = @{@"test": @"data"};
    NSError *jsonError;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:requestBody options:0 error:&jsonError];
    XCTAssertNil(jsonError, @"Failed to serialize request body: %@", jsonError);

    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected status code 200, got %ld", (long)httpResponse.statusCode);

        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"x-echo-server"], @"FastAPI", @"Expected FastAPI echo server header");

        NSError *parseError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        XCTAssertNil(parseError, @"Failed to parse response JSON: %@", parseError);

        // Verify response data
        XCTAssertEqualObjects(responseData[@"method"], @"PUT", @"Expected PUT method in response");
        XCTAssertEqualObjects(responseData[@"headers"][@"content-type"], @"application/json", @"Expected content-type header in response");

        // Verify the echoed body
        NSString *bodyContent = responseData[@"body"];
        XCTAssertNotNil(bodyContent, @"Expected body content in response");
        XCTAssertTrue([bodyContent containsString:@"test"], @"Expected request body to be echoed back");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)postRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_ECHO]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"POST";

    // Add request body
    NSDictionary *requestBody = @{
        @"name": @"test_user",
        @"age": @25,
        @"email": @"test@example.com"
    };
    NSError *jsonError;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:requestBody options:0 error:&jsonError];
    XCTAssertNil(jsonError, @"Failed to serialize request body: %@", jsonError);

    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected status code 200, got %ld", (long)httpResponse.statusCode);

        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"x-echo-server"], @"FastAPI", @"Expected FastAPI echo server header");

        NSError *parseError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        XCTAssertNil(parseError, @"Failed to parse response JSON: %@", parseError);

        // Verify response data
        XCTAssertEqualObjects(responseData[@"method"], @"POST", @"Expected POST method in response");
        XCTAssertEqualObjects(responseData[@"headers"][@"content-type"], @"application/json", @"Expected content-type header in response");

        // Verify the echoed body contains our data
        NSString *bodyContent = responseData[@"body"];
        XCTAssertNotNil(bodyContent, @"Expected body content in response");
        XCTAssertTrue([bodyContent containsString:@"test_user"], @"Expected name in echoed body");
        XCTAssertTrue([bodyContent containsString:@"test@example.com"], @"Expected email in echoed body");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)optionsRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_ECHO]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    request.HTTPMethod = @"OPTIONS";

    // Add CORS headers
    [request setValue:@"*" forHTTPHeaderField:@"Access-Control-Request-Headers"];
    [request setValue:@"PUT, DELETE" forHTTPHeaderField:@"Access-Control-Request-Method"];
    [request setValue:@"example.com" forHTTPHeaderField:@"Origin"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected status code 200, got %ld", (long)httpResponse.statusCode);

        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"x-echo-server"], @"FastAPI", @"Expected FastAPI echo server header");

        XCTAssertEqualObjects(responseHeaders[@"Access-Control-Allow-Origin"], @"example.com", @"Expected Origin to be echoed back");
        XCTAssertEqualObjects(responseHeaders[@"Access-Control-Allow-Methods"], @"PUT, DELETE", @"Expected allowed methods to be echoed back");
        XCTAssertEqualObjects(responseHeaders[@"Access-Control-Allow-Headers"], @"*", @"Expected allowed headers to be echoed back");
        XCTAssertEqualObjects(responseHeaders[@"Access-Control-Max-Age"], @"86400", @"Expected max age header to be present");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)getRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_ECHO]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    // Add some custom headers
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"EMASCurl-Test/1.0" forHTTPHeaderField:@"User-Agent"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected status code 200, got %ld", (long)httpResponse.statusCode);

        // Verify response headers
        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"x-echo-server"], @"FastAPI", @"Expected FastAPI echo server header");
        XCTAssertEqualObjects(responseHeaders[@"content-type"], @"application/json", @"Expected JSON content type");

        // Parse and verify response body
        NSError *parseError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        XCTAssertNil(parseError, @"Failed to parse response JSON: %@", parseError);

        // Verify response data
        XCTAssertEqualObjects(responseData[@"method"], @"GET", @"Expected GET method in response");
        XCTAssertTrue([responseData[@"url"] hasSuffix:PATH_ECHO], @"Expected URL to end with %@", PATH_ECHO);

        // Verify echoed headers
        NSDictionary *headers = responseData[@"headers"];
        XCTAssertEqualObjects(headers[@"accept"], @"application/json", @"Expected Accept header in response");
        XCTAssertEqualObjects(headers[@"user-agent"], @"EMASCurl-Test/1.0", @"Expected User-Agent header in response");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)getRedirectRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_REDIRECT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected final status code 200, got %ld", (long)httpResponse.statusCode);

        // Verify response headers
        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"x-echo-server"], @"FastAPI", @"Expected FastAPI echo server header");
        XCTAssertEqualObjects(responseHeaders[@"content-type"], @"application/json", @"Expected JSON content type");

        // Parse and verify response body
        NSError *parseError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        XCTAssertNil(parseError, @"Failed to parse response JSON: %@", parseError);

        // Verify we ended up at the /echo endpoint
        XCTAssertTrue([responseData[@"url"] hasSuffix:@"/echo"], @"Expected URL to end with /echo");
        XCTAssertEqualObjects(responseData[@"method"], @"GET", @"Expected GET method in response");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)getRedirectChainRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_REDIRECT_CHAIN]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected final status code 200, got %ld", (long)httpResponse.statusCode);

        // Verify response headers
        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"x-echo-server"], @"FastAPI", @"Expected FastAPI echo server header");
        XCTAssertEqualObjects(responseHeaders[@"content-type"], @"application/json", @"Expected JSON content type");

        // Parse and verify response body
        NSError *parseError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        XCTAssertNil(parseError, @"Failed to parse response JSON: %@", parseError);

        // Verify we ended up at the /echo endpoint after following the chain
        XCTAssertTrue([responseData[@"url"] hasSuffix:@"/echo"], @"Expected URL to end with /echo");
        XCTAssertEqualObjects(responseData[@"method"], @"GET", @"Expected GET method in response");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
}

- (void)getGzipResponse:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_GZIP_RESPONSE]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Request failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected status code 200, got %ld", (long)httpResponse.statusCode);

        NSDictionary *responseHeaders = httpResponse.allHeaderFields;
        XCTAssertEqualObjects(responseHeaders[@"content-encoding"], @"gzip", @"Expected gzip content encoding");
        XCTAssertEqualObjects(responseHeaders[@"content-type"], @"application/json", @"Expected JSON content type");

        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Failed to parse JSON response: %@", jsonError);
        XCTAssertEqualObjects(jsonResponse[@"message"], @"This is a gzipped response", @"Unexpected response message");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0, @"Request timed out");
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
