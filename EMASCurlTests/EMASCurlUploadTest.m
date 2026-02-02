//
//  EMASCurlUploadTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2024/12/16.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

// Custom NSInputStream for chunked transfer testing
@interface EMASChunkedInputStream : NSInputStream

@property (nonatomic, assign) NSInteger totalSize;
@property (nonatomic, assign) NSInteger bytesGenerated;
@property (nonatomic, assign) NSStreamStatus streamStatus;
@property (nonatomic, strong) NSError *streamError;

- (instancetype)initWithTotalSize:(NSInteger)totalSize;

@end

@implementation EMASChunkedInputStream

@synthesize streamStatus = _streamStatus;
@synthesize streamError = _streamError;

- (instancetype)initWithTotalSize:(NSInteger)totalSize {
    self = [super init];
    if (self) {
        _totalSize = totalSize;
        _bytesGenerated = 0;
        _streamStatus = NSStreamStatusNotOpen;
        _streamError = nil;
    }
    return self;
}

- (void)open {
    self.streamStatus = NSStreamStatusOpen;
}

- (void)close {
    self.streamStatus = NSStreamStatusClosed;
}


- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len {
    if (self.streamStatus != NSStreamStatusOpen) {
        return -1;
    }

    if (self.bytesGenerated >= self.totalSize) {
        self.streamStatus = NSStreamStatusAtEnd;
        return 0;
    }

    // Generate data on the fly (simulating unknown size)
    NSInteger bytesToGenerate = MIN(len, self.totalSize - self.bytesGenerated);
    for (NSInteger i = 0; i < bytesToGenerate; i++) {
        buffer[i] = (uint8_t)((self.bytesGenerated + i) % 256);
    }

    self.bytesGenerated += bytesToGenerate;

    if (self.bytesGenerated >= self.totalSize) {
        self.streamStatus = NSStreamStatusAtEnd;
    }

    return bytesToGenerate;
}

- (BOOL)getBuffer:(uint8_t * _Nullable *)buffer length:(NSUInteger *)len {
    // We don't provide a buffer - force the caller to use read:maxLength:
    return NO;
}

- (BOOL)hasBytesAvailable {
    return self.streamStatus == NSStreamStatusOpen && self.bytesGenerated < self.totalSize;
}

@end

@interface EMASCurlUploadTestBase : XCTestCase

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *progressValues;
@property (nonatomic, copy) void (^completionBlock)(NSData *data, NSURLResponse *response, NSError *error);

@end

@implementation EMASCurlUploadTestBase

- (void)setUp {
    [super setUp];
    self.progressValues = [NSMutableArray array];
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
    NSString *boundary = @"Boundary-EMASCurlUploadTest";
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

- (void)uploadData:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSData *testData = [self generateTestData:1024 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"test.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASCurlUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *task = [self.session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [[NSFileManager defaultManager] removeItemAtPath:formDataPath error:nil];

        XCTAssertNil(error, @"Upload failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");

        NSError *jsonError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Failed to parse response JSON");
        XCTAssertNotNil(responseData[@"size"], @"Response should contain file size");
        XCTAssertEqual([responseData[@"size"] integerValue], 1024 * 1024, @"File size should be exactly 1MB");

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)uploadDataWithProgress:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSData *testData = [self generateTestData:1024 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"test.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASCurlUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    self.progressValues = [NSMutableArray array];

    __weak typeof(self) weakSelf = self;

    [EMASCurlProtocol setUploadProgressUpdateBlockForRequest:request uploadProgressUpdateBlock:^(NSURLRequest * _Nonnull request, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
        typeof(self) strongSelf = weakSelf;
        double progress = (double)totalBytesSent / totalBytesExpectedToSend;
        [strongSelf.progressValues addObject:@(progress)];
    }];

    NSURLSessionUploadTask *task = [self.session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:formDataPath error:nil];

        XCTAssertNil(error, @"Upload failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        typeof(self) strongSelf = weakSelf;
        XCTAssertNotNil(strongSelf, @"Self was deallocated");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");

        NSError *jsonError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Failed to parse response JSON");
        XCTAssertNotNil(responseData[@"size"], @"Response should contain file size");
        XCTAssertEqual([responseData[@"size"] integerValue], 1024 * 1024, @"File size should be exactly 1MB");

        XCTAssertGreaterThan(strongSelf.progressValues.count, 0, @"Should have received progress updates");
        XCTAssertEqualWithAccuracy([[strongSelf.progressValues lastObject] doubleValue], 1.0, 0.01, @"Final progress should be 100%%");

        double previousProgress = 0;
        for (NSNumber *progress in strongSelf.progressValues) {
            XCTAssertGreaterThanOrEqual([progress doubleValue], previousProgress, @"Progress should increase monotonically");
            previousProgress = [progress doubleValue];
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Upload request timed out");
}

- (void)uploadDataAndCancel:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSData *testData = [self generateTestData:1024 * 1024 * 10];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"test_large.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASCurlUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    self.progressValues = [NSMutableArray array];

    __weak typeof(self) weakSelf = self;

    __block NSMutableArray<NSURLSessionUploadTask *> *requestWrapper = [NSMutableArray new];

    [EMASCurlProtocol setUploadProgressUpdateBlockForRequest:request uploadProgressUpdateBlock:^(NSURLRequest * _Nonnull request, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
        double progress = 0;
        if (totalBytesExpectedToSend > 0) {
            progress = (double)totalBytesSent / totalBytesExpectedToSend;
        }
        typeof(self) strongSelf = weakSelf;
        [strongSelf.progressValues addObject:@(progress)];
        if (progress > 0.3) {
            [requestWrapper[0] cancel];
        }
    }];

    NSURLSessionUploadTask *task = [self.session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:formDataPath error:nil];

        XCTAssertNotNil(error, @"Expected error due to cancellation");
        XCTAssertEqual(error.code, -999, @"Expected cancellation error code");

        typeof(self) strongSelf = weakSelf;
        XCTAssertLessThan([[strongSelf.progressValues lastObject] doubleValue], 0.8, @"Final progress should be less than 80%%");

        dispatch_semaphore_signal(semaphore);
    }];

    [requestWrapper addObject:task];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Upload request timed out");
}

- (void)uploadDataUsingHttpBody:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_PUT_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PUT";

    NSData *testData = [self generateTestData:512 * 1024];
    [request setHTTPBody:testData];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Upload failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)patchUploadUsingHttpBody:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_PATCH_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PATCH";

    // Create PATCH request body - simulate partial update data
    NSDictionary *patchData = @{
        @"operation": @"update",
        @"updates": @{
            @"status": @"active",
            @"lastModified": [NSDate date].description
        }
    };

    NSError *jsonError;
    NSData *testData = [NSJSONSerialization dataWithJSONObject:patchData options:0 error:&jsonError];
    XCTAssertNil(jsonError, @"Failed to create PATCH JSON data: %@", jsonError);

    [request setHTTPBody:testData];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"PATCH upload failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code for PATCH");

        // Verify response contains upload information
        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            XCTAssertTrue([responseString containsString:@"size"], @"PATCH response should contain size information");
            XCTAssertTrue([responseString containsString:@"PATCH"], @"PATCH response should contain method information");
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)deleteUploadUsingHttpBody:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_DELETE_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"DELETE";

    // Create DELETE request body - simulate deletion with metadata
    NSDictionary *deleteData = @{
        @"deletion_reason": @"user_requested",
        @"items_to_delete": @[@123, @456, @789],
        @"options": @{
            @"create_backup": @YES,
            @"notify_admin": @YES,
            @"soft_delete": @NO
        }
    };

    NSError *jsonError;
    NSData *testData = [NSJSONSerialization dataWithJSONObject:deleteData options:0 error:&jsonError];
    XCTAssertNil(jsonError, @"Failed to create DELETE JSON data: %@", jsonError);

    [request setHTTPBody:testData];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"DELETE upload failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code for DELETE");

        // Verify response contains upload information
        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            XCTAssertTrue([responseString containsString:@"size"], @"DELETE response should contain size information");
            XCTAssertTrue([responseString containsString:@"DELETE"], @"DELETE response should contain method information");
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)uploadDataWithChunkedEncoding:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_CHUNKED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // Create a simple data stream without Content-Length
    NSData *testData = [@"Test chunked upload data from EMASCurl" dataUsingEncoding:NSUTF8StringEncoding];
    request.HTTPBodyStream = [NSInputStream inputStreamWithData:testData];

    // DO NOT set Content-Length header to trigger chunked encoding
    // The protocol will detect no Content-Length and use chunked transfer

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Chunked upload error: %@", error);
        }
        if (data) {
            NSString *responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"Server response: %@", responseStr);
        }

        XCTAssertNil(error, @"Chunked upload failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code, got %ld", (long)httpResponse.statusCode);

        // Parse response
        NSError *jsonError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Failed to parse response JSON");

        // Verify chunked encoding was used
        BOOL isChunked = [responseData[@"is_chunked"] boolValue];
        NSString *contentLengthHeader = responseData[@"content_length_header"];
        NSInteger actualSize = [responseData[@"actual_size"] integerValue];

        XCTAssertTrue(isChunked, @"Server should report chunked encoding was used. is_chunked=%@", responseData[@"is_chunked"]);
        XCTAssertNil(contentLengthHeader, @"Content-Length header should not be present but was: %@", contentLengthHeader);
        XCTAssertEqual(actualSize, 38, @"Actual received size should match. Got %ld", (long)actualSize); // "Test chunked upload data from EMASCurl" = 38 bytes
        XCTAssertEqualObjects(responseData[@"method"], @"POST", @"Method should be POST");

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Chunked upload request timed out");
}

- (void)uploadDataWithChunkedEncodingAndProgress:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_POST_CHUNKED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // Create larger test data for progress tracking
    NSMutableData *testData = [NSMutableData dataWithCapacity:1024 * 100]; // 100KB
    for (int i = 0; i < 100; i++) {
        NSData *chunk = [@"This is a test chunk of data for chunked upload testing. " dataUsingEncoding:NSUTF8StringEncoding];
        [testData appendData:chunk];
    }
    NSInteger expectedSize = testData.length;
    request.HTTPBodyStream = [NSInputStream inputStreamWithData:testData];

    // DO NOT set Content-Length header

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    self.progressValues = [NSMutableArray array];

    __weak typeof(self) weakSelf = self;

    [EMASCurlProtocol setUploadProgressUpdateBlockForRequest:request uploadProgressUpdateBlock:^(NSURLRequest * _Nonnull request, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
        typeof(self) strongSelf = weakSelf;
        // For chunked encoding, totalBytesExpectedToSend should be -1 (unknown)
        if (totalBytesExpectedToSend == -1) {
            // Just track bytes sent
            [strongSelf.progressValues addObject:@(totalBytesSent)];
        } else {
            double progress = (double)totalBytesSent / totalBytesExpectedToSend;
            [strongSelf.progressValues addObject:@(progress)];
        }
    }];

    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Chunked upload with progress failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        typeof(self) strongSelf = weakSelf;
        XCTAssertNotNil(strongSelf, @"Self was deallocated");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");

        // Parse response
        NSError *jsonError;
        NSDictionary *responseData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        XCTAssertNil(jsonError, @"Failed to parse response JSON");

        // Verify chunked encoding was used
        XCTAssertTrue([responseData[@"is_chunked"] boolValue], @"Server should report chunked encoding was used");
        XCTAssertEqual([responseData[@"actual_size"] integerValue], expectedSize, @"Actual received size should match");

        // Verify we got progress updates
        XCTAssertGreaterThan(strongSelf.progressValues.count, 0, @"Should have received progress updates");

        // Progress values should be increasing
        NSInteger previousBytes = 0;
        for (NSNumber *value in strongSelf.progressValues) {
            NSInteger currentBytes = [value integerValue];
            XCTAssertGreaterThanOrEqual(currentBytes, previousBytes, @"Progress should increase monotonically");
            previousBytes = currentBytes;
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Chunked upload with progress request timed out");
}

@end

@interface EMASCurlUploadTestHttp11 : EMASCurlUploadTestBase

@end

@implementation EMASCurlUploadTestHttp11

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setDebugLogEnabled:YES];

    // 创建 EMASCurl 配置
    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;  // 显式设置 HTTP1

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testUploadData {
    [self uploadData:HTTP11_ENDPOINT];
}

- (void)testUploadDataWithProgress {
    [self uploadDataWithProgress:HTTP11_ENDPOINT];
}

- (void)testUploadDataAndCancel {
    [self uploadDataAndCancel:HTTP11_ENDPOINT];
}

- (void)testCancelUploadAndUploadAgain {
    [self uploadDataAndCancel:HTTP11_ENDPOINT];
    [self uploadData:HTTP11_ENDPOINT];
}

- (void)testUploadDataUsingHttpBody {
    [self uploadDataUsingHttpBody:HTTP11_ENDPOINT];
}

- (void)testPatchUploadUsingHttpBody {
    [self patchUploadUsingHttpBody:HTTP11_ENDPOINT];
}

- (void)testDeleteUploadUsingHttpBody {
    [self deleteUploadUsingHttpBody:HTTP11_ENDPOINT];
}

- (void)testUploadDataWithChunkedEncoding {
    [self uploadDataWithChunkedEncoding:HTTP11_ENDPOINT];
}

- (void)testUploadDataWithChunkedEncodingAndProgress {
    [self uploadDataWithChunkedEncodingAndProgress:HTTP11_ENDPOINT];
}

@end

@interface EMASCurlUploadTestHttp2 : EMASCurlUploadTestBase

@end

@implementation EMASCurlUploadTestHttp2

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setDebugLogEnabled:YES];

    // 创建 EMASCurl 配置
    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    // HTTP2 是默认值，无需显式设置

    // 设置自签名证书的 CA 证书
    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *certPath = [testBundle pathForResource:@"ca" ofType:@"crt"];
    XCTAssertNotNil(certPath, @"Certificate file not found in test bundle.");
    curlConfig.caFilePath = certPath;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testUploadData {
    [self uploadData:HTTP2_ENDPOINT];
}

- (void)testUploadDataWithProgress {
    [self uploadDataWithProgress:HTTP2_ENDPOINT];
}


- (void)testUploadDataAndCancel {
    [self uploadDataAndCancel:HTTP2_ENDPOINT];
}

- (void)testCancelUploadAndUploadAgain {
    [self uploadDataAndCancel:HTTP2_ENDPOINT];
    [self uploadData:HTTP2_ENDPOINT];
}

- (void)testUploadDataUsingHttpBody {
    [self uploadDataUsingHttpBody:HTTP2_ENDPOINT];
}

- (void)testPatchUploadUsingHttpBody {
    [self patchUploadUsingHttpBody:HTTP2_ENDPOINT];
}

- (void)testDeleteUploadUsingHttpBody {
    [self deleteUploadUsingHttpBody:HTTP2_ENDPOINT];
}

- (void)testUploadDataWithChunkedEncoding {
    // Note: HTTP/2 doesn't use chunked transfer encoding in the same way as HTTP/1.1
    // HTTP/2 uses frames for data transfer. This test verifies our protocol handles it correctly.
    // For HTTP/2, we skip this test as it's not relevant
    // [self uploadDataWithChunkedEncoding:HTTP2_ENDPOINT];
    XCTSkip(@"HTTP/2 doesn't use chunked transfer encoding");
}

- (void)testUploadDataWithChunkedEncodingAndProgress {
    // Skip for HTTP/2 as well
    XCTSkip(@"HTTP/2 doesn't use chunked transfer encoding");
}

@end
