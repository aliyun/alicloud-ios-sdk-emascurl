//
//  EMASCurlNetworkSession.m

#import "EMASCurlNetworkSession.h"
#import "EMASCurlNetworkOperationQueue.h"
#import "EMASCurlNetworkManager.h"
#import "EMASCurlSafeArray.h"
#import "EMASCurlUtils.h"
#import <os/lock.h>

NSTimeInterval const kEMASCurlPriorityNormalTimeoutInterval = 15;
NSTimeInterval const kEMASCurlPriorityVeryHighTimeoutInterval = 1;

#pragma mark - NetworkSession配置 (对相同的EMASCurlNetworkSession实例生效)
@implementation EMASCurlNetworkSessionConfiguration
- (instancetype)init
{
    self = [super init];
    if (self) {
        _cacheCountLimit = 0;
        _cacheCostLimit = 0;
        _retryLimit = 0;
        _networkTimeoutInterval = kEMASCurlPriorityNormalTimeoutInterval;
    }
    return self;
}
@end

#pragma mark - DataTask (建议一个请求对应一个该实例)

@interface EMASCurlNetworkDataTask ()<EMASCurlNetworkURLCacheHandle>
@property (nullable, readwrite, copy) NSURLRequest  *originalRequest;
@property (nonatomic, strong) EMASCurlNetworkAsyncOperation *operation;
@property (nonatomic, assign) BOOL isCancel;
@property (nonatomic, assign) BOOL canCache;
@property (nonatomic, assign) NSUInteger retryCount; // 已重试次数

@property (nonatomic, strong) EMASCurlNetworkSessionConfiguration *configuration;
@property (nonatomic, weak) EMASCurlNetworkSession *networkSession;

@property (nonatomic, copy) EMASCurlNetResponseCallback responseCallback;
@property (nonatomic, copy) EMASCurlNetDataCallback dataCallback;
@property (nonatomic, copy) EMASCurlNetSuccessCallback successCallback;
@property (nonatomic, copy) EMASCurlNetFailCallback failCallback;
@property (nonatomic, copy) EMASCurlNetRedirectCallback redirectCallback;
@property (nonatomic, copy) EMASCurlNetProgressCallBack progressCallBack;
@end

@implementation EMASCurlNetworkDataTask
- (instancetype)initWithRequest:(NSURLRequest *)request
                  configuration:(EMASCurlNetworkSessionConfiguration *)configuration {
    self = [super init];
    if (self) {
        _originalRequest = request;
        _configuration = configuration;
        _dataTaskPriority = EMASCurlNetworkDataTaskPriorityNormal;
        _retryLimit = configuration.retryLimit;
        _retryCount = 0;
        _isCancel = NO;
        _canCache = YES;
    }
    return self;
}

- (void)resume {
    NSMutableURLRequest *requestM = [self.originalRequest mutableCopy];
    requestM.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    if (self.retryCount > 0) {
        requestM.timeoutInterval = requestM.timeoutInterval * 2;
    } else {
        requestM.timeoutInterval = self.configuration.networkTimeoutInterval;
    }
    self.originalRequest = [requestM copy];
    
    EMASCurlNetworkAsyncOperation *operation = [[EMASCurlNetworkAsyncOperation alloc] initWithRequest:self.originalRequest canCache:self.canCache];
    operation.responseCallback = self.responseCallback;
    operation.dataCallback = self.dataCallback;
    operation.successCallback = self.successCallback;
    operation.progressCallback = self.progressCallBack;
    EMASCurlWeak(self)
    operation.failCallback = ^(NSError * _Nonnull error) {
        EMASCurlStrong(self)
        if (error.code != -999) {
        }
        if (!self) {
            return;
        }
        
        if (error &&
            error.code == -1001 &&
            [self.originalRequest.HTTPMethod isEqualToString:@"GET"] &&
            self.retryCount < self.retryLimit) {
            [self retry];
            return;
        }
        self.failCallback(error);
    };
    operation.redirectCallback = self.redirectCallback;
    operation.URLCacheHandler = self;
    switch (self.dataTaskPriority) {
        case EMASCurlNetworkDataTaskPriorityVeryHigh:
            operation.queuePriority = NSOperationQueuePriorityVeryHigh;
            break;
        case EMASCurlNetworkDataTaskPriorityHigh:
            operation.queuePriority = NSOperationQueuePriorityHigh;
            break;
        default:
            operation.queuePriority = NSOperationQueuePriorityNormal;
            break;
    }
    self.operation = operation;
    [[EMASCurlNetworkOperationQueue defaultQueue] addOperation:operation];
}

- (void)cancel {
    if (self.isCancel) {
        return;
    }
    [self.operation cancel];
    self.isCancel = YES;
    [self.networkSession cancelTask:self];
}

- (void)retry {
    self.retryCount ++;
    [self cancel];
    
    if (!self.networkSession) {
        return;
    }
    EMASCurlNetworkDataTask *retryDataTask = [self.networkSession
                                        dataTaskWithRequest:self.originalRequest
                                        responseCallback:self.responseCallback
                                        dataCallback:self.dataCallback
                                        successCallback:self.successCallback
                                        failCallback:self.failCallback
                                        redirectCallback:self.redirectCallback];
    if (!retryDataTask) {
        return;
    }
    retryDataTask.retryLimit = self.retryLimit;
    retryDataTask.retryCount = self.retryCount;
    retryDataTask.dataTaskPriority = EMASCurlNetworkDataTaskPriorityHigh;
    [retryDataTask resume];
}

#pragma mark - EMASCurlNetworkURLCacheHandle

- (BOOL)URLCacheEnable {
    return YES;
}

- (BOOL)isOvercapacityWithCost:(NSUInteger)cost {
    return [self.networkSession isOvercapacityWithCost:cost];
}

- (void)updateCacheCapacityWithCost:(NSUInteger)cost {
    [self.networkSession updateCacheCapacityWithCost:cost];
}

@end

#pragma mark - NetworkSession (建议一个webview实例对应一个该实例)
@interface EMASCurlNetworkSession ()
@property (nonatomic, strong) EMASCurlNetworkSessionConfiguration *configuration;
@property (nonatomic, strong) EMASCurlSafeArray<EMASCurlNetworkDataTask *> *tasksArrayM;

@property (nonatomic, assign) NSUInteger currentCacheCount; // 当前缓存数量
@property (nonatomic, assign) NSUInteger currentCacheCost; // 当前缓存容量

@end

@implementation EMASCurlNetworkSession{
    os_unfair_lock _tasksArraylock;
}

+ (instancetype)sessionWithConfiguation:(EMASCurlNetworkSessionConfiguration *)configuration  {
    return [[self alloc] initWithConfiguation:configuration];
}

- (instancetype)initWithConfiguation:(EMASCurlNetworkSessionConfiguration *)configuration{
    self = [super init];
    if (self) {
        _tasksArraylock = OS_UNFAIR_LOCK_INIT;
        _configuration = configuration;
        _tasksArrayM = [EMASCurlSafeArray strongObjects];
        _currentCacheCost = 0;
        _currentCacheCount = 0;
    }
    return self;
}

- (nullable EMASCurlNetworkDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                                   responseCallback:(EMASCurlNetResponseCallback)responseCallback
                                       dataCallback:(EMASCurlNetDataCallback)dataCallback
                                    successCallback:(EMASCurlNetSuccessCallback)successCallback
                                       failCallback:(EMASCurlNetFailCallback)failCallback
                                   redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback {
    
    return [self dataTaskWithRequest:request responseCallback:responseCallback progressCallBack:nil dataCallback:dataCallback successCallback:successCallback failCallback:failCallback redirectCallback:redirectCallback];
    
}

- (EMASCurlNetworkDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                          responseCallback:(EMASCurlNetResponseCallback)responseCallback
                          progressCallBack:(EMASCurlNetProgressCallBack)progressCallBack
                              dataCallback:(EMASCurlNetDataCallback)dataCallback
                           successCallback:(EMASCurlNetSuccessCallback)successCallback
                              failCallback:(EMASCurlNetFailCallback)failCallback
                          redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback
{
    EMASCurlNetworkDataTask *dataTask = [[EMASCurlNetworkDataTask alloc] initWithRequest:request
                                                               configuration:self.configuration];
    dataTask.responseCallback = responseCallback;
    dataTask.dataCallback = dataCallback;
    EMASCurlWeak(dataTask)
    EMASCurlWeak(self)
    dataTask.successCallback = ^{
        EMASCurlStrong(dataTask)
        EMASCurlStrong(self)
        if (!self || !dataTask) {
            return;
        }
        if (successCallback) {
            successCallback();
        }
        [self cancelTask:dataTask];
    };
    dataTask.failCallback = ^(NSError * _Nonnull error) {
        EMASCurlStrong(dataTask)
        EMASCurlStrong(self)
        if (!self || !dataTask) {
            return;
        }
        if (failCallback) {
            failCallback(error);
        }
        [self cancelTask:dataTask];
    };
    dataTask.redirectCallback = redirectCallback;
    dataTask.progressCallBack = progressCallBack;
    dataTask.networkSession = self;
    
    BOOL notGet = ![request.HTTPMethod.lowercaseString isEqualToString:@"get"];
    NSString *mainUrl = request.mainDocumentURL.absoluteString;
    NSString *requestUrl = request.URL.absoluteString;
    BOOL isMainUrl = [EMASCurlUtils isValidStr:mainUrl] && [EMASCurlUtils isEqualURLA:requestUrl withURLB:mainUrl];
    
    if (notGet || isMainUrl) { // 不是get请求或者是mainURL，明显不缓存
        dataTask.canCache = NO;
    } else {
        dataTask.canCache = YES;
    }
    
    os_unfair_lock_lock(&_tasksArraylock);
    [_tasksArrayM addObject:dataTask];
    os_unfair_lock_unlock(&_tasksArraylock);
    
    [_tasksArrayM addObject:dataTask];
    return dataTask;
}

- (BOOL)isOvercapacityWithCost:(NSUInteger)cost {
    if (self.configuration.cacheCountLimit != 0 &&
        self.currentCacheCount >= self.configuration.cacheCountLimit) {
        return YES;
    }
    if (self.configuration.cacheCostLimit != 0 &&
        self.currentCacheCost + cost > self.configuration.cacheCostLimit) {
        return YES;
    }
    return NO;
}

- (void)updateCacheCapacityWithCost:(NSUInteger)cost {
    if (self.configuration.cacheCountLimit != 0) {
        self.currentCacheCount ++;
    }
    if (self.configuration.cacheCostLimit != 0) {
        self.currentCacheCost += cost;
    }
}

- (void)cancelTask:(EMASCurlNetworkDataTask *)task {
    [task cancel];
    os_unfair_lock_lock(&_tasksArraylock);
    [self.tasksArrayM removeObject:task];
    os_unfair_lock_unlock(&_tasksArraylock);
    
}

- (void)cancelAllTasks {
    if (self.tasksArrayM.count == 0) {
        return;
    }
    NSArray<EMASCurlNetworkDataTask *> *dataTaskArr = [NSArray array];
    os_unfair_lock_lock(&_tasksArraylock);
    dataTaskArr = [self.tasksArrayM copy];
    os_unfair_lock_unlock(&_tasksArraylock);
    
    for (EMASCurlNetworkDataTask *task in dataTaskArr) {
        [task cancel];
        os_unfair_lock_lock(&_tasksArraylock);
        [self.tasksArrayM removeObject:task];
        os_unfair_lock_unlock(&_tasksArraylock);
    }
}


@end

