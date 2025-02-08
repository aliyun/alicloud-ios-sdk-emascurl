//
//  EMASCurlNetworkSession.m
//

#import "EMASCurlWebNetworkManager.h"
#import "EMASCurlWebRequestExecutor.h"
#import "EMASCurlWebUtils.h"
#import "EMASCurlWebURLResponseCache.h"
#import <os/lock.h>

@interface EMASCurlWebNetworkManager ()

@property (nonatomic, strong) EMASCurlSafeArray<EMASCurlNetworkDataTask *> *dataTasks;
@property (nonatomic, assign) NSUInteger currentCacheItemCount;
@property (nonatomic, assign) NSUInteger currentCacheCapacity;

@property (nonatomic, strong) EMASCurlWebRequestExecutor *networkManager;
@property (nonatomic, strong) EMASCurlWebURLResponseCache *httpResponseCache;

@end

@implementation EMASCurlWebNetworkManager {
    os_unfair_lock _dataTasksLock;
}

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration
                               cacheDelegate:(id<EMASCurlWebCacheProtocol>)delegate {
    self = [super init];
    if (self) {
        _dataTasksLock = OS_UNFAIR_LOCK_INIT;
        _dataTasks = [EMASCurlSafeArray new];
        _currentCacheCapacity = 0;
        _currentCacheItemCount = 0;

        _networkManager = [[EMASCurlWebRequestExecutor alloc] initWithSessionConfiguration:sessionConfiguration];
        _httpResponseCache = [[EMASCurlWebURLResponseCache alloc] initWithDelegate:delegate];
    }
    return self;
}

- (nullable EMASCurlNetworkDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                                        responseCallback:(EMASCurlNetResponseCallback)responseCallback
                                            dataCallback:(EMASCurlNetDataCallback)dataCallback
                                         successCallback:(EMASCurlNetSuccessCallback)successCallback
                                            failCallback:(EMASCurlNetFailCallback)failCallback
                                        redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback {
    EMASCurlNetworkDataTask *dataTask = [[EMASCurlNetworkDataTask alloc] initWithRequest:request];
    dataTask.responseCallback = responseCallback;
    dataTask.dataCallback = dataCallback;
    dataTask.redirectCallback = redirectCallback;
    dataTask.networkManagerWeakRef = self.networkManager;
    dataTask.httpCacheWeakRef = self.httpResponseCache;

    EMASCurlWeak(self)
    EMASCurlWeak(dataTask)
    dataTask.retryHandler = ^{
        EMASCurlStrong(self)
        EMASCurlStrong(dataTask)
        EMASCurlNetworkDataTask *retryTask = [self dataTaskWithRequest:dataTask.originalRequest
                                                      responseCallback:dataTask.responseCallback
                                                          dataCallback:dataTask.dataCallback
                                                       successCallback:dataTask.successCallback
                                                          failCallback:dataTask.failCallback
                                                      redirectCallback:dataTask.redirectCallback];
        if (!retryTask) {
            return;
        }
        retryTask.currentRetryCount = dataTask.currentRetryCount;
        [retryTask resume];
    };

    dataTask.cancelHandler = ^{
        EMASCurlStrong(self)
        EMASCurlStrong(dataTask)
        [self cancelTask:dataTask];
    };

    dataTask.successCallback = ^{
        EMASCurlStrong(dataTask)
        EMASCurlStrong(self)
        if (!self || !dataTask) return;
        if (successCallback) {
            successCallback();
        }
        [self removeDataTask:dataTask];
    };
    dataTask.failCallback = ^(NSError * _Nonnull error) {
        EMASCurlStrong(dataTask)
        EMASCurlStrong(self)
        if (!self || !dataTask) return;
        if (failCallback) {
            failCallback(error);
        }
        [self removeDataTask:dataTask];
    };

    // 根据请求方法判断是否允许缓存
    BOOL isNonGET = ![[request.HTTPMethod uppercaseString] isEqualToString:@"GET"];
    NSString *mainDocumentURL = request.mainDocumentURL.absoluteString;
    NSString *requestURL = request.URL.absoluteString;
    BOOL isMainURLMatch = ([EMASCurlWebUtils isValidStr:mainDocumentURL] &&
                           [EMASCurlWebUtils isEqualURLA:requestURL withURLB:mainDocumentURL]);
    if (isNonGET || isMainURLMatch) {
        dataTask.canCache = NO;
    } else {
        dataTask.canCache = YES;
    }

    os_unfair_lock_lock(&_dataTasksLock);
    [self.dataTasks addObject:dataTask];
    os_unfair_lock_unlock(&_dataTasksLock);

    return dataTask;
}

// 取消指定任务
- (void)cancelTask:(EMASCurlNetworkDataTask *)task {
    [task cancel];
    [self removeDataTask:task];
}

// 取消所有任务
- (void)cancelAllTasks {
    os_unfair_lock_lock(&_dataTasksLock);
    NSArray<EMASCurlNetworkDataTask *> *tasksCopy = [self.dataTasks copy];
    os_unfair_lock_unlock(&_dataTasksLock);

    for (EMASCurlNetworkDataTask *task in tasksCopy) {
        [task cancel];
        [self removeDataTask:task];
    }
}

// 从任务列表中移除
- (void)removeDataTask:(EMASCurlNetworkDataTask *)task {
    os_unfair_lock_lock(&_dataTasksLock);
    [self.dataTasks removeObject:task];
    os_unfair_lock_unlock(&_dataTasksLock);
}

@end
