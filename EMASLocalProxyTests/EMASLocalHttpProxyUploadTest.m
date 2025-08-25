//
//  EMASLocalHttpProxyUploadTest.m
//  EMASLocalProxyTests
//
//  Created by xuyecan on 2025/08/25.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASLocalProxy/EMASLocalProxy.h>
#import "EMASLocalProxyTestConstants.h"

@interface EMASLocalHttpProxyUploadTestBase : XCTestCase

@property (nonatomic, strong) NSMutableArray<NSNumber *> *progressValues;

+ (void)setupProxySessionWithDelegate:(id<NSURLSessionDelegate>)delegate;
- (void)performBasicUploadTest:(NSString *)endpoint;

@end

static NSURLSession *session;

@implementation EMASLocalHttpProxyUploadTestBase

- (void)setUp {
    [super setUp];
    self.progressValues = [NSMutableArray array];
}

+ (void)setupProxySessionWithDelegate:(id<NSURLSessionDelegate>)delegate {
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

    // 创建配置了本地代理的URLSession
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPShouldUsePipelining = YES;
    config.HTTPShouldSetCookies = YES;

    BOOL proxyConfigured = [EMASLocalHttpProxy installIntoUrlSessionConfiguration:config];
    XCTAssertTrue(proxyConfigured, @"Local proxy should be installed successfully");

    session = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];
}

- (void)performBasicUploadTest:(NSString *)endpoint {
    // Test basic upload to verify EMASLocalProxy upload works
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_PUT_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PUT";

    // Generate small test data
    NSData *testData = [self generateTestData:1024];
    [request setHTTPBody:testData];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSLog(@"Basic upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"HTTP Response status: %ld", (long)(httpResponse ? httpResponse.statusCode : -1));

        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"Response body: %@", responseString);
        }

        // Verify upload succeeded
        XCTAssertNil(error, @"Basic upload should succeed");

        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code, got %ld", (long)httpResponse.statusCode);
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)), 0, @"Basic upload request timed out");
}

- (NSData *)generateTestData:(NSUInteger)size {
    NSMutableData *data = [NSMutableData dataWithCapacity:size];
    for (NSUInteger i = 0; i < size; i++) {
        uint8_t byte = (uint8_t)(i % 256);
        [data appendBytes:&byte length:1];
    }
    return data;
}

- (NSString *)createTemporaryFileWithData:(NSData *)data {
    NSString *tempDir = NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"upload_test_%@.bin", [[NSUUID UUID] UUIDString]];
    NSString *filePath = [tempDir stringByAppendingPathComponent:fileName];
    [data writeToFile:filePath atomically:YES];
    return filePath;
}

- (NSString *)createMultipartFormDataFileWithData:(NSData *)data filename:(NSString *)filename {
    NSString *boundary = @"Boundary-EMASLocalProxyUploadTest";
    NSMutableData *formData = [NSMutableData data];

    // Add form field boundary
    [formData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    // Add content disposition header
    [formData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", filename] dataUsingEncoding:NSUTF8StringEncoding]];
    // Add content type header
    [formData appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    // Add file data
    [formData appendData:data];
    // Add closing boundary
    [formData appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    // Write to temporary file
    NSString *tempDir = NSTemporaryDirectory();
    NSString *formDataPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"form_data_%@", [[NSUUID UUID] UUIDString]]];
    [formData writeToFile:formDataPath atomically:YES];

    return formDataPath;
}

- (void)testUploadLargeFileWith403Error:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_SLOW_403]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 生成1.5MB测试数据，确保会触发403错误
    NSData *testData = [self generateTestData:1536 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"large_test.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASLocalProxyUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:formDataPath error:nil];

        NSLog(@"Upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"HTTP Response status: %ld", (long)(httpResponse ? httpResponse.statusCode : -1));

        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"Response body: %@", responseString);
        }

        // 验证收到了403错误 - 可能通过NSError或HTTP状态码
        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 403, @"Expected 403 status code, got %ld", (long)httpResponse.statusCode);
        } else {
            XCTAssertNotNil(error, @"Expected either 403 response or error");
        }

        NSLog(@"Large file upload with 403 error test completed");
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)), 0, @"Upload request with 403 error timed out");
}

- (void)testUploadLargeFileWith403ErrorUsingPUT:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_PUT_SLOW_403]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PUT";

    // 生成1.5MB测试数据，确保会触发403错误
    NSData *testData = [self generateTestData:1536 * 1024];
    [request setHTTPBody:testData];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSLog(@"PUT upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"HTTP Response status: %ld", (long)(httpResponse ? httpResponse.statusCode : -1));

        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"Response body: %@", responseString);
        }

        // 验证收到了403错误 - 可能通过NSError或HTTP状态码
        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 403, @"Expected 403 status code, got %ld", (long)httpResponse.statusCode);
            NSLog(@"Received expected 403 error during PUT upload");
        } else {
            XCTAssertNotNil(error, @"Expected either 403 response or error");
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)), 0, @"PUT upload request with 403 error timed out");
}

- (void)testUploadFileWithImmediate403Error:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_IMMEDIATE_403]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // 生成1MB测试数据
    NSData *testData = [self generateTestData:1024 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"test.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASLocalProxyUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:formDataPath error:nil];

        NSLog(@"Upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"HTTP Response status: %ld", (long)(httpResponse ? httpResponse.statusCode : -1));

        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"Response body: %@", responseString);
        }

        // 验证收到了403错误 - 可能通过NSError或HTTP状态码
        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 403, @"Expected 403 status code, got %ld", (long)httpResponse.statusCode);
        } else {
            XCTAssertNotNil(error, @"Expected either 403 response or error");
        }

        NSLog(@"Immediate 403 error test completed");
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Upload request with immediate 403 error timed out");
}

- (void)testUploadFileWithImmediate403ErrorUsingPUT:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_PUT_IMMEDIATE_403]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PUT";

    // 生成1MB测试数据
    NSData *testData = [self generateTestData:1024 * 1024];
    [request setHTTPBody:testData];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSLog(@"PUT upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"HTTP Response status: %ld", (long)(httpResponse ? httpResponse.statusCode : -1));

        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"Response body: %@", responseString);
        }

        // 验证收到了403错误 - 可能通过NSError或HTTP状态码
        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 403, @"Expected 403 status code, got %ld", (long)httpResponse.statusCode);
            NSLog(@"Received expected immediate 403 error during PUT upload");
        } else {
            XCTAssertNotNil(error, @"Expected either 403 response or error");
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"PUT upload request with immediate 403 error timed out");
}

- (void)testUploadSmallFileMultipart:(NSString *)endpoint {
    // Test small multipart file upload
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // Generate 10KB test data
    NSData *testData = [self generateTestData:10 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"small_test.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASLocalProxyUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:formDataPath error:nil];

        NSLog(@"Small file upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        XCTAssertNil(error, @"Small file upload should succeed");
        XCTAssertNotNil(response, @"Should receive response");

        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code, got %ld", (long)httpResponse.statusCode);
        }

        if (data) {
            NSError *jsonError;
            NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            XCTAssertNil(jsonError, @"Response should be valid JSON");
            XCTAssertNotNil(responseData[@"size"], @"Response should contain file size");
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)), 0, @"Small file upload timed out");
}

- (void)testUploadMediumFilePUT:(NSString *)endpoint {
    // Test medium size file upload using PUT
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_PUT_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PUT";

    // Generate 100KB test data
    NSData *testData = [self generateTestData:100 * 1024];
    [request setHTTPBody:testData];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSLog(@"Medium file upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        XCTAssertNil(error, @"Medium file upload should succeed");
        XCTAssertNotNil(response, @"Should receive response");

        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code, got %ld", (long)httpResponse.statusCode);
        }

        if (data) {
            NSError *jsonError;
            NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            XCTAssertNil(jsonError, @"Response should be valid JSON");
            XCTAssertNotNil(responseData[@"size"], @"Response should contain file size");
            XCTAssertEqual([responseData[@"size"] integerValue], 100 * 1024, @"File size should be 100KB");
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)), 0, @"Medium file upload timed out");
}

- (void)testUploadLargeFileMultipart:(NSString *)endpoint {
    // Test large multipart file upload (under 500KB to avoid 403)
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // Generate 300KB test data (less than 500KB threshold)
    NSData *testData = [self generateTestData:300 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"large_test.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASLocalProxyUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:formDataPath error:nil];

        NSLog(@"Large file upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        XCTAssertNil(error, @"Large file upload should succeed");
        XCTAssertNotNil(response, @"Should receive response");

        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code, got %ld", (long)httpResponse.statusCode);
        }

        if (data) {
            NSError *jsonError;
            NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            XCTAssertNil(jsonError, @"Response should be valid JSON");
            XCTAssertNotNil(responseData[@"size"], @"Response should contain file size");
            XCTAssertEqual([responseData[@"size"] integerValue], 300 * 1024, @"File size should be 300KB");
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)), 0, @"Large file upload timed out");
}

- (void)testUploadEmptyFile:(NSString *)endpoint {
    // Test empty file upload
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_PUT_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PUT";

    // Empty data
    NSData *testData = [NSData data];
    [request setHTTPBody:testData];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSLog(@"Empty file upload completed with error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        XCTAssertNil(error, @"Empty file upload should succeed");
        XCTAssertNotNil(response, @"Should receive response");

        if (httpResponse) {
            XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code, got %ld", (long)httpResponse.statusCode);
        }

        if (data) {
            NSError *jsonError;
            NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            XCTAssertNil(jsonError, @"Response should be valid JSON");
            XCTAssertNotNil(responseData[@"size"], @"Response should contain file size");
            XCTAssertEqual([responseData[@"size"] integerValue], 0, @"File size should be 0");
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Empty file upload timed out");
}

@end

#pragma mark - HTTP Tests (Plain Connection)

@interface EMASLocalHttpProxyUploadTestHTTP : EMASLocalHttpProxyUploadTestBase

@end

@implementation EMASLocalHttpProxyUploadTestHTTP

+ (void)setUp {
    [EMASLocalHttpProxyUploadTestBase setupProxySessionWithDelegate:nil];
}

- (void)testUploadLargeFileWith403Error {
    [self testUploadLargeFileWith403Error:HTTP_ENDPOINT];
}

- (void)testUploadLargeFileWith403ErrorUsingPUT {
    [self testUploadLargeFileWith403ErrorUsingPUT:HTTP_ENDPOINT];
}

- (void)testUploadFileWithImmediate403Error {
    [self testUploadFileWithImmediate403Error:HTTP_ENDPOINT];
}

- (void)testUploadFileWithImmediate403ErrorUsingPUT {
    [self testUploadFileWithImmediate403ErrorUsingPUT:HTTP_ENDPOINT];
}

- (void)testBasicUploadFunctionality {
    [self performBasicUploadTest:HTTP_ENDPOINT];
}

- (void)testUploadSmallFileMultipart {
    [self testUploadSmallFileMultipart:HTTP_ENDPOINT];
}

- (void)testUploadMediumFilePUT {
    [self testUploadMediumFilePUT:HTTP_ENDPOINT];
}

- (void)testUploadLargeFileMultipart {
    [self testUploadLargeFileMultipart:HTTP_ENDPOINT];
}

- (void)testUploadEmptyFile {
    [self testUploadEmptyFile:HTTP_ENDPOINT];
}

@end

#pragma mark - HTTPS Tests (CONNECT Tunnel)

@interface EMASLocalHttpProxyUploadTestHTTPS : EMASLocalHttpProxyUploadTestBase <NSURLSessionDelegate>

@end

@implementation EMASLocalHttpProxyUploadTestHTTPS

+ (void)setUp {
    [EMASLocalHttpProxyUploadTestBase setupProxySessionWithDelegate:[[EMASLocalHttpProxyUploadTestHTTPS alloc] init]];
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

- (void)testUploadLargeFileWith403Error {
    [self testUploadLargeFileWith403Error:HTTPS_ENDPOINT];
}

- (void)testUploadLargeFileWith403ErrorUsingPUT {
    [self testUploadLargeFileWith403ErrorUsingPUT:HTTPS_ENDPOINT];
}

- (void)testUploadFileWithImmediate403Error {
    [self testUploadFileWithImmediate403Error:HTTPS_ENDPOINT];
}

- (void)testUploadFileWithImmediate403ErrorUsingPUT {
    [self testUploadFileWithImmediate403ErrorUsingPUT:HTTPS_ENDPOINT];
}

- (void)testUploadSmallFileMultipart {
    [self testUploadSmallFileMultipart:HTTPS_ENDPOINT];
}

- (void)testUploadMediumFilePUT {
    [self testUploadMediumFilePUT:HTTPS_ENDPOINT];
}

- (void)testUploadLargeFileMultipart {
    [self testUploadLargeFileMultipart:HTTPS_ENDPOINT];
}

- (void)testUploadEmptyFile {
    [self testUploadEmptyFile:HTTPS_ENDPOINT];
}

- (void)testBasicUploadFunctionality {
    [self performBasicUploadTest:HTTPS_ENDPOINT];
}

@end
