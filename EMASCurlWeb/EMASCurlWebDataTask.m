//
//  EMASCurlWebDataTask.m
//  EMASCurl
//
//  Created by xuyecan on 2025/2/5.
//

#import "EMASCurlWebDataTask.h"
#import "EMASCurlWebUtils.h"
#import "EMASCurlWebLogger.h"
#import "NSCachedURLResponse+EMASCurl.h"

NSInteger const kEMASCurlGetRequestRetryLimit = 0;

@interface EMASCurlNetworkDataTask ()

@property (nonatomic, assign) BOOL isCancelled;
@property (nonatomic, assign) RequestTaskIdentifier requestID;
@property (nonatomic, strong) NSHTTPURLResponse *receivedResponse;
@property (nonatomic, strong) NSMutableData *receivedData;

@end

@implementation EMASCurlNetworkDataTask

- (instancetype)initWithRequest:(NSURLRequest *)request {
    self = [super init];
    if (self) {
        _originalRequest = request;
        _currentRetryCount = 0;
        _isCancelled = NO;
        _requestID = -1;
        _receivedData = [NSMutableData data];
    }
    return self;
}

#pragma mark - Public Methods

- (void)resume {
    if (self.isCancelled) {
        return;
    }

    // 设置请求优先级对应的超时时间
    NSMutableURLRequest *mutableRequest = [self.originalRequest mutableCopy];

    // 强制不使用系统缓存
    mutableRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    self.originalRequest = [mutableRequest copy];

    // 发起网络请求
    EMASCurlWeak(self)
    self.requestID = [self.networkManagerWeakRef
                      startWithRequest:self.originalRequest
                      responseCallback:^(NSURLResponse * _Nonnull response) {
        EMASCurlStrong(self)
        [self handleResponse:response];
    }
        dataCallback:^(NSData * _Nonnull data) {
        EMASCurlStrong(self)
        [self handleData:data];
    } successCallback:^{
        EMASCurlStrong(self)
        [self handleSuccess];
    } failCallback:^(NSError * _Nonnull error) {
        EMASCurlStrong(self)
        [self handleFailure:error];
    } redirectCallback:^(NSURLResponse * _Nonnull resp, NSURLRequest * _Nonnull newReq, EMASCurlNetRedirectDecisionCallback decisionCb) {
        EMASCurlStrong(self)
        [self handleRedirect:resp newRequest:newReq decisionCallback:decisionCb];
    }];
}

- (void)cancel {
    if (self.isCancelled) {
        return;
    }
    self.isCancelled = YES;
    [self.networkManagerWeakRef cancelWithRequestIdentifier:self.requestID];
    if (self.cancelHandler) {
        self.cancelHandler();
    }
}

#pragma mark - Callback Handling

// 处理响应回调
- (void)handleResponse:(NSURLResponse *)response {
    self.receivedResponse = (NSHTTPURLResponse *)response;

    if (self.responseCallback) {
        self.responseCallback(response);
    }
}

// 处理数据回调
- (void)handleData:(NSData *)data {
    [self.receivedData appendData:data];
    if (self.dataCallback) {
        self.dataCallback(data);
    }
}

// 处理成功回调
- (void)handleSuccess {
    if (self.successCallback) {
        self.successCallback();
    }
}

// 处理失败回调
- (void)handleFailure:(NSError *)error {
    // 重试条件：超时错误且为GET请求，并且未超出重试次数
    BOOL isTimeout = (error.code == -1001);
    BOOL isGetMethod = [[self.originalRequest.HTTPMethod uppercaseString] isEqualToString:@"GET"];
    if (isTimeout && isGetMethod && self.currentRetryCount < kEMASCurlGetRequestRetryLimit) {
        EMASCurlCacheLog(@"Request failed and we retry, url: %@, error: %@", self.originalRequest.URL.absoluteString, error);
        [self performRetry];
        return;
    }
    if (self.failCallback) {
        EMASCurlCacheLog(@"Request failed and we give up, url: %@, error: %@", self.originalRequest.URL.absoluteString, error);
        self.failCallback(error);
    }
}

// 处理重定向回调
- (void)handleRedirect:(NSURLResponse *)response
            newRequest:(NSURLRequest *)redirectRequest
     decisionCallback:(EMASCurlNetRedirectDecisionCallback)decisionCallback {
    // 直接透传给上层
    if (self.redirectCallback) {
        self.redirectCallback(response, redirectRequest, decisionCallback);
    } else {
        decisionCallback(YES);
    }
}

#pragma mark - Internal Retry

- (void)performRetry {
    self.currentRetryCount++;

    // 先取消当前任务
    [self cancel];

    if (self.retryHandler) {
        self.retryHandler();
    }
}

@end
