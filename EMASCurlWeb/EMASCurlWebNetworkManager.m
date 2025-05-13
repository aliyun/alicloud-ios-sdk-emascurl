//
//  EMASCurlNetworkSession.m
//

#import "EMASCurlWebNetworkManager.h"
#import "EMASCurlWebRequestExecutor.h"
#import "EMASCurlWebUtils.h"
#import <os/lock.h>

@interface EMASCurlWebNetworkManager ()

@property (nonatomic, strong) EMASCurlSafeArray<EMASCurlNetworkDataTask *> *dataTasks;
@property (nonatomic, assign) NSUInteger currentCacheItemCount;
@property (nonatomic, assign) NSUInteger currentCacheCapacity;

@property (nonatomic, strong) EMASCurlWebRequestExecutor *networkManager;

@end

@implementation EMASCurlWebNetworkManager {
    os_unfair_lock _dataTasksLock;
}

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration {
    self = [super init];
    if (self) {
        _dataTasksLock = OS_UNFAIR_LOCK_INIT;
        _dataTasks = [EMASCurlSafeArray new];
        _currentCacheCapacity = 0;
        _currentCacheItemCount = 0;

        _networkManager = [[EMASCurlWebRequestExecutor alloc] initWithSessionConfiguration:sessionConfiguration];
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
