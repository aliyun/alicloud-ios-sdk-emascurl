//
//  EMASCurlTests.m
//  EMASCurlTests
//
//  Created by xin yu on 2024/10/29.
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "GCDWebServerManager.h"
#import <OCMock/OCMock.h>

static id _mockNSBundle;

@interface EMASNetTests : XCTestCase

@end

@implementation EMASNetTests

+ (void)setUp {
    // Suite-level setup method called before the class begins to run any of its test methods or their associated per-instance setUp methods.
    [super setUp];
    [[GCDWebServerManager sharedManager] startServer];
    [NSThread sleepForTimeInterval:5.0];

    _mockNSBundle = [OCMockObject niceMockForClass:[NSBundle class]];
    NSBundle *correctMainBundle = [NSBundle bundleForClass:self.class];
    [[[[_mockNSBundle stub] classMethod] andReturn:correctMainBundle] mainBundle];
}

+ (void)tearDown {
    // Suite-level teardown method called after the class has finished running all of its test methods and their associated per-instance tearDown methods and teardown blocks.
    [[GCDWebServerManager sharedManager] stopServer];
    [super tearDown];
}

#pragma mark ===================== HTTP/1.1 test =====================

#pragma mark * NSURLSessionDataTask test

- (void)testHttp1DataTaskGet {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/hello", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(EMASCURL_TESTHTML, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskHead {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/hello", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"HEAD"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(@"", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskPostWithBody {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/post", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[EMASCURL_TESTDATA dataUsingEncoding:NSUTF8StringEncoding]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(EMASCURL_TESTDATA, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskPostWithBodyStream {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/post", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBodyStream:[NSInputStream inputStreamWithData:[EMASCURL_TESTDATA dataUsingEncoding:NSUTF8StringEncoding]]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(EMASCURL_TESTDATA, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskPostWithNoBody {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/post", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(@"", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskPUTWithBody {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/put", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:[EMASCURL_TESTDATA dataUsingEncoding:NSUTF8StringEncoding]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(EMASCURL_TESTDATA, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskPUTWithBodyStream {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/put", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBodyStream:[NSInputStream inputStreamWithData:[EMASCURL_TESTDATA dataUsingEncoding:NSUTF8StringEncoding]]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(EMASCURL_TESTDATA, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskPUTWithNoBody {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/put", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PUT"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(@"", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskRedirect {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/redirect", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(EMASCURL_TESTHTML, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DataTaskGzip {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/gzip", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(EMASCURL_TESTHTML, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

#pragma mark * NSURLSessionUploadTask test

- (void)testHttp1UploadTask {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/put", EMASCURL_TESTPORT]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PUT"];

    NSBundle *mainBundle = [NSBundle bundleForClass:[self class]];
    NSString *filePath = [mainBundle pathForResource:@"test" ofType:@"txt"];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *uploadTask = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertTrue([data isEqualToData:[NSData dataWithContentsOfFile:filePath]]);

        dispatch_semaphore_signal(semaphore);
    }];
    [uploadTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

#pragma mark * NSURLSessionDownloadTask test

- (void)testHttp1DownloadTask {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/download", EMASCURL_TESTPORT]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        NSBundle *mainBundle = [NSBundle bundleForClass:[self class]];
        NSString *filePath = [mainBundle pathForResource:@"test" ofType:@"txt"];
        XCTAssertTrue([[NSData dataWithContentsOfURL:location] isEqualToData:[NSData dataWithContentsOfFile:filePath]]);

        dispatch_semaphore_signal(semaphore);
    }];
    [downloadTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp1DownloadTaskChunkedEncoding {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP1];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/chunked", EMASCURL_TESTPORT]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        NSBundle *mainBundle = [NSBundle bundleForClass:[self class]];
        NSString *filePath = [mainBundle pathForResource:@"test" ofType:@"txt"];
        XCTAssertTrue([[NSData dataWithContentsOfURL:location] isEqualToData:[NSData dataWithContentsOfFile:filePath]]);

        dispatch_semaphore_signal(semaphore);
    }];
    [downloadTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

#pragma mark ===================== HTTP/2 test =====================

#pragma mark * NSURLSessionDataTask test

- (void)testHttp2DataTaskGet {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"GET", methodValue);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskHead {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"HEAD"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqualObjects(@"", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskPostWithBody {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[EMASCURL_TESTDATA dataUsingEncoding:NSUTF8StringEncoding]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"POST", methodValue);

        NSDictionary *formDict = jsonObject[@"form"];
        XCTAssertEqualObjects(formDict[EMASCURL_TESTDATA], @"");

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskPostWithBodyStream {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBodyStream:[NSInputStream inputStreamWithData:[EMASCURL_TESTDATA dataUsingEncoding:NSUTF8StringEncoding]]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"POST", methodValue);

        NSDictionary *formDict = jsonObject[@"form"];
        XCTAssertEqualObjects(formDict[EMASCURL_TESTDATA], @"");

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskPostWithNoBody {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"POST", methodValue);

        NSDictionary *formDict = jsonObject[@"form"];
        XCTAssertNil(formDict[EMASCURL_TESTDATA]);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskPutWithBody {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:[EMASCURL_TESTDATA dataUsingEncoding:NSUTF8StringEncoding]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"PUT", methodValue);

        NSString *dataString = jsonObject[@"data"];
        XCTAssertEqualObjects(dataString, EMASCURL_TESTDATA);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskPutWithBodyStream {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBodyStream:[NSInputStream inputStreamWithData:[EMASCURL_TESTDATA dataUsingEncoding:NSUTF8StringEncoding]]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"PUT", methodValue);

        NSString *dataString = jsonObject[@"data"];
        XCTAssertEqualObjects(dataString, EMASCURL_TESTDATA);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskPUTWithNoBody {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PUT"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"PUT", methodValue);

        XCTAssertEqualObjects(jsonObject[@"data"], @"");

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskRedirect {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/redirect-to?url=https://httpbin.org/anything&status_code=301"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"GET", methodValue);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)testHttp2DataTaskGzip {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/gzip"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"GET", methodValue);

        NSNumber *gzipped = jsonObject[@"gzipped"];
        XCTAssertEqualObjects(@(1), gzipped);

        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

#pragma mark * NSURLSessionUploadTask test

- (void)testHttp2UploadTask {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PUT"];

    NSBundle *mainBundle = [NSBundle bundleForClass:[self class]];
    NSString *filePath = [mainBundle pathForResource:@"test" ofType:@"txt"];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *uploadTask = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"PUT", methodValue);

        NSString *dataString = jsonObject[@"data"];
        XCTAssertEqualObjects(dataString, [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:filePath] encoding:NSUTF8StringEncoding]);

        dispatch_semaphore_signal(semaphore);
    }];
    [uploadTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

#pragma mark * NSURLSessionDownloadTask test

- (void)testHttp2DownloadTask {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];

    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);

        NSError *jsonError;
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:location] options:0 error:&jsonError];
        XCTAssertNil(jsonError);

        NSString *methodValue = jsonObject[@"method"];
        XCTAssertEqualObjects(@"GET", methodValue);

        dispatch_semaphore_signal(semaphore);
    }];
    [downloadTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

@end
