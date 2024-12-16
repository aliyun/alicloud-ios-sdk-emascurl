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

@interface EMASCurlDownloadTestBase : XCTestCase

@end

@implementation EMASCurlDownloadTestBase

- (void)downloadBinaryData:(const NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(response);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        XCTAssertEqual(httpResponse.statusCode, 200);
        XCTAssertEqual(1024 * 1024, [data length]);

        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)downloadBinaryDataAndCancel:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        XCTAssertNotNil(error);
        XCTAssertEqual(-999, error.code);
        dispatch_semaphore_signal(semaphore);
    }];

    [dataTask resume];

    [NSThread sleepForTimeInterval:2];

    [dataTask cancel];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
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
    [self downloadBinaryData:HTTP11_ENDPOINT];
}

- (void)testDownloadBinaryDataAndCancel {
    [self downloadBinaryDataAndCancel:HTTP11_ENDPOINT];
}

- (void)testCancelDownloadAndDownloadAgain {
    [self downloadBinaryDataAndCancel:HTTP11_ENDPOINT];
    [self downloadBinaryData:HTTP11_ENDPOINT];
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
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testDownloadBinaryData {
    [self downloadBinaryData:HTTP2_ENDPOINT];
}

- (void)testDownloadBinaryDataAndCancel {
    [self downloadBinaryDataAndCancel:HTTP2_ENDPOINT];
}

- (void)testCancelDownloadAndDownloadAgain {
    [self downloadBinaryDataAndCancel:HTTP2_ENDPOINT];
    [self downloadBinaryData:HTTP2_ENDPOINT];
}

@end
