//
//  EMASCurlConcurrentTest.m
//  EMASCurlTests
//
//  Created by Assistant on 2024/12/24.
//  并发下载测试
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurl.h>
#import "EMASCurlTestConstants.h"

@interface EMASCurlConcurrentTestBase : XCTestCase <NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSMutableArray<NSURLSessionDataTask *> *activeTasks;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *completedRequestsCount;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *failedRequestsCount;
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSTimer *continuousTimer;
@property (nonatomic, assign) NSInteger currentConcurrency;
@property (nonatomic, assign) NSInteger maxConcurrency;
@property (nonatomic, assign) NSInteger totalRequestsSent;
@property (nonatomic, assign) NSInteger totalRequestsCompleted;
@property (nonatomic, assign) NSInteger totalRequestsFailed;
@property (nonatomic, strong) dispatch_semaphore_t testSemaphore;

@end

@implementation EMASCurlConcurrentTestBase

- (void)setUp {
    [super setUp];
    self.activeTasks = [NSMutableArray array];
    self.completedRequestsCount = [NSMutableArray array];
    self.failedRequestsCount = [NSMutableArray array];
    self.operationQueue = [[NSOperationQueue alloc] init];
    self.operationQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;

    self.currentConcurrency = 0;
    self.maxConcurrency = 100;
    self.totalRequestsSent = 0;
    self.totalRequestsCompleted = 0;
    self.totalRequestsFailed = 0;
}

- (void)tearDown {
    [self.continuousTimer invalidate];
    self.continuousTimer = nil;

    // 取消所有活跃任务
    for (NSURLSessionDataTask *task in self.activeTasks) {
        [task cancel];
    }
    [self.activeTasks removeAllObjects];

    [super tearDown];
}

#pragma mark - 测试辅助方法

- (void)downloadData:(NSString *)endpoint
         completion:(void (^)(BOOL success, NSError *error))completion {

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    // 线程安全地更新计数器
    @synchronized(self) {
        self.currentConcurrency++;
        self.totalRequestsSent++;
    }

    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 线程安全地更新计数器
        @synchronized(self) {
            self.currentConcurrency--;

            if (error) {
                self.totalRequestsFailed++;
                NSLog(@"Download failed: %@", error.localizedDescription);
            } else {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                if (httpResponse.statusCode == 200 && data.length == 1024 * 1024) {
                    self.totalRequestsCompleted++;
                } else {
                    self.totalRequestsFailed++;
                    NSLog(@"Download validation failed: status=%ld, size=%lu", (long)httpResponse.statusCode, (unsigned long)data.length);
                }
            }
        }

        if (completion) {
            completion(error == nil, error);
        }
    }];

    // 添加到活跃任务列表，用于清理
    @synchronized(self.activeTasks) {
        [self.activeTasks addObject:dataTask];
    }

    [dataTask resume];
}

#pragma mark - 并发测试方法

- (void)testConcurrentDownloads:(NSString *)endpoint {
    const NSInteger numberOfRequests = 20;
    dispatch_group_t group = dispatch_group_create();

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:numberOfRequests];
    for (int i = 0; i < numberOfRequests; i++) {
        [results addObject:@NO];
    }

    for (int i = 0; i < numberOfRequests; i++) {
        dispatch_group_enter(group);

        [self downloadData:endpoint completion:^(BOOL success, NSError *error) {
            @synchronized(results) {
                results[i] = @(success);
            }
            dispatch_group_leave(group);
        }];
    }

    // 等待所有下载完成（最多60秒）
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC);
    XCTAssertEqual(dispatch_group_wait(group, timeout), 0, @"Concurrent downloads timed out");

    // 验证结果
    NSInteger successCount = 0;
    for (NSNumber *result in results) {
        if ([result boolValue]) {
            successCount++;
        }
    }

    XCTAssertEqual(successCount, numberOfRequests, @"Expected all %ld downloads to succeed, got %ld", (long)numberOfRequests, (long)successCount);
    XCTAssertEqual(self.totalRequestsCompleted, numberOfRequests, @"Completed requests count mismatch");
    XCTAssertEqual(self.totalRequestsFailed, 0, @"Should have no failed requests");
}

- (void)testHighConcurrencyDownloads:(NSString *)endpoint {
    const NSInteger numberOfRequests = 50;
    dispatch_group_t group = dispatch_group_create();

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:numberOfRequests];
    for (int i = 0; i < numberOfRequests; i++) {
        [results addObject:@NO];
    }

    // 一次性启动所有请求来测试高并发
    for (int i = 0; i < numberOfRequests; i++) {
        dispatch_group_enter(group);

        [self downloadData:endpoint completion:^(BOOL success, NSError *error) {
            @synchronized(results) {
                results[i] = @(success);
            }
            dispatch_group_leave(group);
        }];
    }

    // 等待所有下载完成（由于负载较高，最多120秒）
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC);
    XCTAssertEqual(dispatch_group_wait(group, timeout), 0, @"High concurrency downloads timed out");

    // 验证结果 - 本地服务器应该100%成功
    NSInteger successCount = 0;
    for (NSNumber *result in results) {
        if ([result boolValue]) {
            successCount++;
        }
    }

    // 期望本地服务器100%成功率
    XCTAssertEqual(successCount, numberOfRequests, @"Expected all %ld downloads to succeed, got %ld", (long)numberOfRequests, (long)successCount);
    XCTAssertEqual(self.totalRequestsCompleted, numberOfRequests, @"Completed requests count mismatch");
    XCTAssertEqual(self.totalRequestsFailed, 0, @"Should have no failed requests with local server");

    NSLog(@"High concurrency test: %ld/%ld requests succeeded", (long)successCount, (long)numberOfRequests);
}

- (void)testContinuousDownloadFor1Minute:(NSString *)endpoint {
    self.testSemaphore = dispatch_semaphore_create(0);

    // 重置计数器
    self.totalRequestsSent = 0;
    self.totalRequestsCompleted = 0;
    self.totalRequestsFailed = 0;
    self.currentConcurrency = 0;

    NSDate *startTime = [NSDate date];
    NSTimeInterval testDuration = 60.0; // 1分钟
    __block BOOL testFinished = NO;
    __block BOOL semaphoreSignaled = NO;

    // 创建调度定时器（在测试中比NSTimer更可靠）
    dispatch_queue_t timerQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timerQueue);

    // 设置定时器每100毫秒触发一次
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);

    // 安全地发信号量的辅助块（只执行一次）
    void (^signalCompletion)(void) = ^{
        @synchronized(self) {
            if (!semaphoreSignaled) {
                semaphoreSignaled = YES;
                NSLog(@"Signaling test completion. Final stats: Sent=%ld, Completed=%ld, Failed=%ld, Active=%ld",
                      (long)self.totalRequestsSent, (long)self.totalRequestsCompleted,
                      (long)self.totalRequestsFailed, (long)self.currentConcurrency);
                dispatch_semaphore_signal(self.testSemaphore);
            }
        }
    };

    dispatch_source_set_event_handler(timer, ^{
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];

        // 1分钟后停止
        if (elapsed >= testDuration) {
            if (!testFinished) {
                testFinished = YES;
                dispatch_source_cancel(timer);

                NSInteger currentActive = 0;
                @synchronized(self) {
                    currentActive = self.currentConcurrency;
                }
                NSLog(@"Test timer finished after %.1f seconds. Waiting for %ld active requests to complete...",
                      elapsed, (long)currentActive);

                // 检查是否可以立即完成
                BOOL canCompleteImmediately = NO;
                @synchronized(self) {
                    canCompleteImmediately = (self.currentConcurrency == 0);
                }
                if (canCompleteImmediately) {
                    signalCompletion();
                    return;
                }

                // 等待一段合理时间让剩余请求完成
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), timerQueue, ^{
                    NSInteger remainingActive = 0;
                    @synchronized(self) {
                        remainingActive = self.currentConcurrency;
                    }
                    NSLog(@"Grace period ended. Forcing completion with %ld active requests.",
                          (long)remainingActive);
                    signalCompletion();
                });
            }
            return;
        }

        // 如果未达到最大并发数且测试未结束则启动请求
        BOOL shouldStartRequest = NO;
        @synchronized(self) {
            shouldStartRequest = (!testFinished && self.currentConcurrency < self.maxConcurrency);
        }

        if (shouldStartRequest) {
            [self downloadData:endpoint completion:^(BOOL success, NSError *error) {
                // 如果测试已结束且没有更多活跃请求则发信号
                BOOL shouldSignal = NO;
                @synchronized(self) {
                    shouldSignal = (testFinished && self.currentConcurrency == 0);
                }
                if (shouldSignal) {
                    signalCompletion();
                }
            }];
        }
    });

    // 启动定时器
    dispatch_resume(timer);

    NSLog(@"Starting continuous download test for 60 seconds with max %ld concurrency...", (long)self.maxConcurrency);

    // 等待测试完成（60秒测试 + 8秒宽限期 + 2秒缓冲 = 70秒）
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 70 * NSEC_PER_SEC);
    long result = dispatch_semaphore_wait(self.testSemaphore, timeout);

    // 清理定时器
    if (!testFinished) {
        testFinished = YES;
        dispatch_source_cancel(timer);
    }

    if (result != 0) {
        NSInteger sent, completed, failed, active;
        @synchronized(self) {
            sent = self.totalRequestsSent;
            completed = self.totalRequestsCompleted;
            failed = self.totalRequestsFailed;
            active = self.currentConcurrency;
        }
        NSLog(@"TEST TIMEOUT - Current state: Sent=%ld, Completed=%ld, Failed=%ld, Active=%ld",
              (long)sent, (long)completed, (long)failed, (long)active);
    }

    XCTAssertEqual(result, 0, @"Continuous download test timed out");

    // 验证结果
    NSInteger finalSent, finalCompleted, finalFailed;
    @synchronized(self) {
        finalSent = self.totalRequestsSent;
        finalCompleted = self.totalRequestsCompleted;
        finalFailed = self.totalRequestsFailed;
    }
    NSLog(@"Continuous download results: Sent=%ld, Completed=%ld, Failed=%ld, Success Rate=%.1f%%",
          (long)finalSent, (long)finalCompleted, (long)finalFailed,
          finalSent > 0 ? (double)finalCompleted / finalSent * 100.0 : 0.0);

    XCTAssertGreaterThan(finalSent, 0, @"Should have sent some requests");
    XCTAssertGreaterThan(finalCompleted, 0, @"Should have completed some requests");

    // 本地服务器期望100%成功率
    XCTAssertEqual(finalCompleted, finalSent, @"Expected all requests to succeed with local server. Sent=%ld, Completed=%ld, Failed=%ld", (long)finalSent, (long)finalCompleted, (long)finalFailed);
    XCTAssertEqual(finalFailed, 0, @"Should have no failed requests with local server");
}

- (void)testConcurrencyLimiting:(NSString *)endpoint {
    const NSInteger requestBatch = 150; // 超过最大并发数
    self.maxConcurrency = 30; // 此测试的较低限制

    // 重置计数器用于此测试
    self.totalRequestsSent = 0;
    self.totalRequestsCompleted = 0;
    self.totalRequestsFailed = 0;

    dispatch_group_t group = dispatch_group_create();
    __block NSInteger maxObservedConcurrency = 0;

    for (int i = 0; i < requestBatch; i++) {
        dispatch_group_enter(group);

        // 轻微延迟以分散请求
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (i * 10) * NSEC_PER_MSEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

            // 仅在低于限制时启动
            BOOL shouldStartRequest = NO;
            @synchronized(self) {
                shouldStartRequest = (self.currentConcurrency < self.maxConcurrency);
                // 跟踪观察到的最大并发数
                if (self.currentConcurrency > maxObservedConcurrency) {
                    maxObservedConcurrency = self.currentConcurrency;
                }
            }

            if (shouldStartRequest) {
                [self downloadData:endpoint completion:^(BOOL success, NSError *error) {
                    dispatch_group_leave(group);
                }];
            } else {
                // 跳过此请求
                dispatch_group_leave(group);
            }
        });
    }

    // 等待完成
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC);
    XCTAssertEqual(dispatch_group_wait(group, timeout), 0, @"Concurrency limiting test timed out");

    NSInteger limitingSent, limitingCompleted, limitingFailed;
    @synchronized(self) {
        limitingSent = self.totalRequestsSent;
        limitingCompleted = self.totalRequestsCompleted;
        limitingFailed = self.totalRequestsFailed;
    }

    NSLog(@"Concurrency limiting test: Max observed concurrency=%ld, Limit=%ld, Sent=%ld, Completed=%ld, Failed=%ld",
          (long)maxObservedConcurrency, (long)self.maxConcurrency,
          (long)limitingSent, (long)limitingCompleted, (long)limitingFailed);

    // 验证并发限制
    XCTAssertLessThanOrEqual(maxObservedConcurrency, self.maxConcurrency + 5, @"Concurrency should not significantly exceed limit");

    // 验证所有发送的请求都成功（本地服务器应该100%成功）
    if (limitingSent > 0) {
        XCTAssertEqual(limitingCompleted, limitingSent, @"Expected all sent requests to succeed with local server. Sent=%ld, Completed=%ld, Failed=%ld", (long)limitingSent, (long)limitingCompleted, (long)limitingFailed);
        XCTAssertEqual(limitingFailed, 0, @"Should have no failed requests with local server");
    }
}

- (void)testRandomCancellation:(NSString *)endpoint {
    const NSInteger numberOfRequests = 30;
    const double cancellationRate = 0.3; // 随机取消30%的请求

    // 重置计数器
    self.totalRequestsSent = 0;
    self.totalRequestsCompleted = 0;
    self.totalRequestsFailed = 0;

    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSURLSessionDataTask *> *allTasks = [NSMutableArray array];
    NSMutableArray<NSNumber *> *taskShouldBeCancelled = [NSMutableArray array];
    NSMutableArray<NSNumber *> *taskResults = [NSMutableArray array]; // YES表示成功，NO表示失败/取消

    // 随机决定哪些请求要被取消
    for (int i = 0; i < numberOfRequests; i++) {
        BOOL shouldCancel = (arc4random_uniform(100) / 100.0) < cancellationRate;
        [taskShouldBeCancelled addObject:@(shouldCancel)];
        [taskResults addObject:@NO]; // 初始化为失败
    }

    NSInteger expectedCancellations = 0;
    for (NSNumber *shouldCancel in taskShouldBeCancelled) {
        if ([shouldCancel boolValue]) {
            expectedCancellations++;
        }
    }

    NSLog(@"Random cancellation test: %ld requests total, %ld will be cancelled, %ld should succeed",
          (long)numberOfRequests, (long)expectedCancellations, (long)(numberOfRequests - expectedCancellations));

    // 启动所有请求
    for (int i = 0; i < numberOfRequests; i++) {
        dispatch_group_enter(group);

        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", endpoint, PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

        // 线程安全地更新计数器
        @synchronized(self) {
            self.totalRequestsSent++;
        }

        NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // 线程安全地更新计数器和结果
            @synchronized(self) {
                if (error) {
                    self.totalRequestsFailed++;
                    // 检查是否是预期的取消错误
                    if (error.code == NSURLErrorCancelled) {
                        NSLog(@"Request %d cancelled as expected", i);
                    } else {
                        NSLog(@"Request %d failed unexpectedly: %@", i, error.localizedDescription);
                    }
                } else {
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                    if (httpResponse.statusCode == 200 && data.length == 1024 * 1024) {
                        self.totalRequestsCompleted++;
                        @synchronized(taskResults) {
                            taskResults[i] = @YES;
                        }
                    } else {
                        self.totalRequestsFailed++;
                        NSLog(@"Request %d validation failed: status=%ld, size=%lu", i, (long)httpResponse.statusCode, (unsigned long)data.length);
                    }
                }
            }

            dispatch_group_leave(group);
        }];

        @synchronized(allTasks) {
            [allTasks addObject:dataTask];
        }

        [dataTask resume];
    }

    // 在随机时间后取消选定的请求（200-800ms之间）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (200 + arc4random_uniform(600)) * NSEC_PER_MSEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(allTasks) {
            for (int i = 0; i < numberOfRequests && i < allTasks.count; i++) {
                if ([taskShouldBeCancelled[i] boolValue]) {
                    NSURLSessionDataTask *task = allTasks[i];
                    [task cancel];
                    NSLog(@"Cancelled request %d", i);
                }
            }
        }
    });

    // 等待所有请求完成或被取消
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC);
    XCTAssertEqual(dispatch_group_wait(group, timeout), 0, @"Random cancellation test timed out");

    // 验证结果
    NSInteger actualSuccesses = 0;
    NSInteger expectedSuccesses = numberOfRequests - expectedCancellations;

    for (int i = 0; i < numberOfRequests; i++) {
        BOOL wasSuccessful = [taskResults[i] boolValue];
        BOOL shouldHaveBeenCancelled = [taskShouldBeCancelled[i] boolValue];

        if (wasSuccessful) {
            actualSuccesses++;
            // 成功的请求不应该是被标记为取消的（除非在取消前就完成了）
            if (shouldHaveBeenCancelled) {
                NSLog(@"Request %d succeeded despite being marked for cancellation (completed before cancel)", i);
            }
        }
    }

    NSInteger randomSent, randomCompleted, randomFailed;
    @synchronized(self) {
        randomSent = self.totalRequestsSent;
        randomCompleted = self.totalRequestsCompleted;
        randomFailed = self.totalRequestsFailed;
    }

    NSLog(@"Random cancellation results: Sent=%ld, Completed=%ld, Failed=%ld, Expected successes=%ld, Actual successes=%ld",
          (long)randomSent, (long)randomCompleted, (long)randomFailed,
          (long)expectedSuccesses, (long)actualSuccesses);

    // 验证基本约束
    XCTAssertEqual(randomSent, numberOfRequests, @"Should have sent exactly %ld requests", (long)numberOfRequests);
    XCTAssertEqual(randomCompleted + randomFailed, numberOfRequests, @"Completed + Failed should equal total sent");

    // 验证成功的请求确实成功了（对于未被取消的请求，期望100%成功）
    // 注意：由于取消的时机是随机的，一些标记为取消的请求可能在取消前就完成了
    XCTAssertGreaterThan(actualSuccesses, 0, @"Should have at least some successful requests");
    XCTAssertEqual(randomCompleted, actualSuccesses, @"Completed count should match successful results");

    // 所有成功的请求都应该是完整的1MB下载
    XCTAssertLessThanOrEqual(actualSuccesses, numberOfRequests, @"Cannot have more successes than total requests");

    // 验证至少有一些请求被取消了（否则测试没有意义）
    XCTAssertGreaterThan(randomFailed, 0, @"Should have some failed/cancelled requests to validate cancellation functionality");
}

@end

#pragma mark - HTTP/1.1 测试

@interface EMASCurlConcurrentTestHttp11 : EMASCurlConcurrentTestBase

@end

@implementation EMASCurlConcurrentTestHttp11

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setLogLevel:EMASCurlLogLevelInfo];

    // 创建 EMASCurl 配置
    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.httpVersion = HTTP1;  // 显式设置 HTTP1

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol installIntoSessionConfiguration:config withConfiguration:curlConfig];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
}

- (void)testConcurrentDownloads {
    [self testConcurrentDownloads:HTTP11_ENDPOINT];
}

- (void)testHighConcurrencyDownloads {
    [self testHighConcurrencyDownloads:HTTP11_ENDPOINT];
}

- (void)testContinuousDownloadFor1Minute {
    [self testContinuousDownloadFor1Minute:HTTP11_ENDPOINT];
}

- (void)testConcurrencyLimiting {
    [self testConcurrencyLimiting:HTTP11_ENDPOINT];
}

- (void)testRandomCancellation {
    [self testRandomCancellation:HTTP11_ENDPOINT];
}

@end

#pragma mark - HTTP/2 测试

@interface EMASCurlConcurrentTestHttp2 : EMASCurlConcurrentTestBase

@end

@implementation EMASCurlConcurrentTestHttp2

- (void)setUp {
    [super setUp];
    [EMASCurlProtocol setLogLevel:EMASCurlLogLevelInfo];

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

- (void)testConcurrentDownloads {
    [self testConcurrentDownloads:HTTP2_ENDPOINT];
}

- (void)testHighConcurrencyDownloads {
    [self testHighConcurrencyDownloads:HTTP2_ENDPOINT];
}

- (void)testContinuousDownloadFor1Minute {
    [self testContinuousDownloadFor1Minute:HTTP2_ENDPOINT];
}

- (void)testConcurrencyLimiting {
    [self testConcurrencyLimiting:HTTP2_ENDPOINT];
}

- (void)testRandomCancellation {
    [self testRandomCancellation:HTTP2_ENDPOINT];
}

@end
