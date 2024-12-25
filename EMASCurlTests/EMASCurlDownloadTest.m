//
//  EMASCurlDownloadTest.m
//  EMASCurlTests
//
//  Created by xuyecan on 2024/12/16.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

static NSURLSession *session;

@interface EMASCurlDownloadTestBase : XCTestCase <NSURLSessionDataDelegate>

@property (nonatomic, assign) int64_t totalBytesReceived;
@property (nonatomic, assign) int64_t expectedTotalBytes;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *progressValues;
@property (nonatomic, copy) void (^completionBlock)(NSData *data, NSURLResponse *response, NSError *error);
@property (nonatomic, copy) void (^progressBlock)(double progress);
@property (nonatomic, strong) NSMutableData *receivedData;

@end

@implementation EMASCurlDownloadTestBase

- (void)setUp {
    [super setUp];
    self.progressValues = [NSMutableArray array];
    self.totalBytesReceived = 0;
    self.expectedTotalBytes = 1024 * 1024;
}

- (void)downloadData:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Download failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");
        XCTAssertEqual(1024 * 1024, [data length], @"Expected 1MB of data");

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    XCTAssertEqual(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0, @"Download request timed out");
}

- (void)downloadDataWithProgress:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    self.totalBytesReceived = 0;
    self.expectedTotalBytes = 1024 * 1024;
    self.progressValues = [NSMutableArray array];
    self.receivedData = [NSMutableData data];

    __weak typeof(self) weakSelf = self;

    self.completionBlock = ^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error, @"Download failed with error: %@", error);
        XCTAssertNotNil(response, @"No response received");

        typeof(self) strongSelf = weakSelf;

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200, @"Expected 200 status code");
        XCTAssertEqual(1024 * 1024, [data length], @"Expected 1MB of data");

        XCTAssertGreaterThan(strongSelf.progressValues.count, 0, @"Should have received progress updates");
        XCTAssertEqualWithAccuracy([[strongSelf.progressValues lastObject] doubleValue], 1.0, 0.01, @"Final progress should be 100%");

        double previousProgress = 0;
        for (NSNumber *progress in strongSelf.progressValues) {
            XCTAssertGreaterThanOrEqual([progress doubleValue], previousProgress, @"Progress should increase monotonically");
            previousProgress = [progress doubleValue];
        }

        dispatch_semaphore_signal(semaphore);
    };

    self.progressBlock = ^(double progress) {
        typeof(self) strongSelf = weakSelf;
        [strongSelf.progressValues addObject:@(progress)];
    };

    NSURLSession *progressSession = [NSURLSession sessionWithConfiguration:[session configuration] delegate:self delegateQueue:nil];
    NSURLSessionDataTask *dataTask = [progressSession dataTaskWithRequest:request];
    [dataTask resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)downloadDataAndCancel:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    self.totalBytesReceived = 0;
    self.expectedTotalBytes = 1024 * 1024;
    self.progressValues = [NSMutableArray array];
    self.receivedData = [NSMutableData data];

    NSURLSession *progressSession = [NSURLSession sessionWithConfiguration:[session configuration] delegate:self delegateQueue:nil];
    NSURLSessionDataTask *dataTask = [progressSession dataTaskWithRequest:request];

    __weak typeof(self) weakSelf = self;

    self.completionBlock = ^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error, @"Expected error due to cancellation");
        XCTAssertEqual(error.code, -999, @"Expected cancellation error code");

        typeof(self) strongSelf = weakSelf;
        XCTAssertLessThan([[strongSelf.progressValues lastObject] doubleValue], 0.5, @"Final progress should less than 50%");

        dispatch_semaphore_signal(semaphore);
    };

    self.progressBlock = ^(double progress) {
        if (progress > 0.3) {
            [dataTask cancel];
        }
        typeof(self) strongSelf = weakSelf;
        [strongSelf.progressValues addObject:@(progress)];
    };

    [dataTask resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {

    [self.receivedData appendData:data];
    self.totalBytesReceived += data.length;
    double progress = (double)self.totalBytesReceived / self.expectedTotalBytes;
    if (self.progressBlock) {
        self.progressBlock(progress);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (self.completionBlock) {
        NSURLSessionDataTask *dataTask = (NSURLSessionDataTask *)task;
        self.completionBlock(self.receivedData, dataTask.response, error);
    }
}

@end

@interface EMASCurlDownloadTestHttp11 : EMASCurlDownloadTestBase

@end

@implementation EMASCurlDownloadTestHttp11

+ (void)setUp {
    [EMASCurlProtocol setDebugLogEnabled:YES];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testDownloadBinaryData {
    [self downloadData:HTTP11_ENDPOINT];
}

- (void)testDownloadDataWithProgress {
    [self downloadDataWithProgress:HTTP11_ENDPOINT];
}

- (void)testDownloadDataAndCancel {
    [self downloadDataAndCancel:HTTP11_ENDPOINT];
}

- (void)testCancelDownloadAndDownloadAgain {
    [self downloadDataAndCancel:HTTP11_ENDPOINT];
    [self downloadData:HTTP11_ENDPOINT];
}

@end

@interface EMASCurlDownloadTestHttp2 : EMASCurlDownloadTestBase

@end

@implementation EMASCurlDownloadTestHttp2

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

- (void)testDownloadBinaryData {
    [self downloadData:HTTP2_ENDPOINT];
}

- (void)testDownloadDataWithProgress {
    [self downloadDataWithProgress:HTTP2_ENDPOINT];
}

- (void)testDownloadDataAndCancel {
    [self downloadDataAndCancel:HTTP2_ENDPOINT];
}

- (void)testCancelDownloadAndDownloadAgain {
    [self downloadDataAndCancel:HTTP2_ENDPOINT];
    [self downloadData:HTTP2_ENDPOINT];
}

@end
