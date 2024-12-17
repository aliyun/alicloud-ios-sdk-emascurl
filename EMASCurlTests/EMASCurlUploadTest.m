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

static NSURLSession *session;

@interface TestUploadProgressHandler : NSObject<EMASCurlUploadProgressHandler>

- (void)setProgressBlock:(void (^)(double progress))block;

@end

@implementation TestUploadProgressHandler

static void (^progressBlock)(double progress);

- (void)setProgressBlock:(void (^)(double progress))block {
    progressBlock = block;
}

#pragma mark - EMASCurlUploadProgressHandler

- (void)uploadWithRequest:(NSURLRequest *)request
          didSendBodyData:(int64_t)bytesSent
           totalBytesSent:(int64_t)totalBytesSent
 totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    if (progressBlock && totalBytesExpectedToSend > 0) {
        double progress = (double)totalBytesSent / totalBytesExpectedToSend;
        progressBlock(progress);
    }
}

@end

@interface EMASCurlUploadTestBase : XCTestCase

@property (nonatomic, assign) int64_t totalBytesSent;
@property (nonatomic, assign) int64_t expectedTotalBytes;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *progressValues;
@property (nonatomic, copy) void (^completionBlock)(NSData *data, NSURLResponse *response, NSError *error);
@property (nonatomic, strong) NSMutableData *receivedData;

@end

@implementation EMASCurlUploadTestBase

- (void)setUp {
    [super setUp];
    self.progressValues = [NSMutableArray array];
    self.totalBytesSent = 0;
    self.expectedTotalBytes = 1024 * 1024; // 1MB
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
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSData *testData = [self generateTestData:1024 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"test.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASCurlUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
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
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSData *testData = [self generateTestData:1024 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"test.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASCurlUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    self.totalBytesSent = 0;
    self.expectedTotalBytes = 1024 * 1024;
    self.progressValues = [NSMutableArray array];
    self.receivedData = [NSMutableData data];

    __weak typeof(self) weakSelf = self;

    TestUploadProgressHandler *uploadProgressHandler = [TestUploadProgressHandler new];

    [uploadProgressHandler setProgressBlock:^(double progress) {
        typeof(self) strongSelf = weakSelf;
        [strongSelf.progressValues addObject:@(progress)];
    }];

    [EMASCurlProtocol setUploadProgressHandler:uploadProgressHandler inRequest:request];

    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
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
        XCTAssertEqualWithAccuracy([[strongSelf.progressValues lastObject] doubleValue], 1.0, 0.01, @"Final progress should be 100%");

        double previousProgress = 0;
        for (NSNumber *progress in strongSelf.progressValues) {
            XCTAssertGreaterThanOrEqual([progress doubleValue], previousProgress, @"Progress should increase monotonically");
            previousProgress = [progress doubleValue];
        }

        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)uploadDataAndCancel:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_UPLOAD_SLOW]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    NSData *testData = [self generateTestData:1024 * 1024];
    NSString *formDataPath = [self createMultipartFormDataFileWithData:testData filename:@"test_large.bin"];
    NSURL *fileURL = [NSURL fileURLWithPath:formDataPath];

    NSString *boundary = @"Boundary-EMASCurlUploadTest";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    self.totalBytesSent = 0;
    self.expectedTotalBytes = 1024 * 1024;
    self.progressValues = [NSMutableArray array];
    self.receivedData = [NSMutableData data];

    __weak typeof(self) weakSelf = self;

    TestUploadProgressHandler *uploadProgressHandler = [TestUploadProgressHandler new];
    [EMASCurlProtocol setUploadProgressHandler:uploadProgressHandler inRequest:request];

    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:formDataPath error:nil];

        XCTAssertNotNil(error, @"Expected error due to cancellation");
        XCTAssertEqual(error.code, -999, @"Expected cancellation error code");

        typeof(self) strongSelf = weakSelf;
        XCTAssertLessThan([[strongSelf.progressValues lastObject] doubleValue], 0.5, @"Final progress should be less than 50%");

        dispatch_semaphore_signal(semaphore);
    }];

    [uploadProgressHandler setProgressBlock:^(double progress) {
        typeof(self) strongSelf = weakSelf;
        [strongSelf.progressValues addObject:@(progress)];
        if (progress > 0.3) {
            [task cancel];
        }
    }];

    [task resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0, @"Upload request timed out");
}

@end

@interface EMASCurlUploadTestHttp11 : EMASCurlUploadTestBase

@end

@implementation EMASCurlUploadTestHttp11

+ (void)setUp {
    [EMASCurlProtocol setDebugLogEnabled:YES];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
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

@end

@interface EMASCurlUploadTestHttp2 : EMASCurlUploadTestBase

@end

@implementation EMASCurlUploadTestHttp2

+ (void)setUp {
    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol setHTTPVersion:HTTP2];

    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *certPath = [testBundle pathForResource:@"ca" ofType:@"crt"];
    XCTAssertNotNil(certPath, @"Certificate file not found in test bundle.");
    [EMASCurlProtocol setSelfSignedCAFilePath:certPath];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
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

@end
