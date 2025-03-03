//
//  EMASCurlNetworkManager.m
//

#import "EMASCurlWebRequestExecutor.h"
#import "EMASCurlWebUtils.h"
#import <WebKit/Webkit.h>

@interface EMASCurlWebNetworkCallbackPack : NSObject

@property (nonatomic, copy) EMASCurlNetResponseCallback responseCallback;
@property (nonatomic, copy) EMASCurlNetDataCallback dataCallback;
@property (nonatomic, copy) EMASCurlNetSuccessCallback successCallback;
@property (nonatomic, copy) EMASCurlNetFailCallback failCallback;
@property (nonatomic, copy) EMASCurlNetRedirectCallback redirectCallback;

- (instancetype)initWithResponseCallback:(EMASCurlNetResponseCallback)responseCallback
                            dataCallback:(EMASCurlNetDataCallback)dataCallback
                         successCallback:(EMASCurlNetSuccessCallback)successCallback
                            failCallback:(EMASCurlNetFailCallback)failCallback
                        redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback;

@end

@implementation EMASCurlWebNetworkCallbackPack

- (instancetype)initWithResponseCallback:(EMASCurlNetResponseCallback)responseCallback
                            dataCallback:(EMASCurlNetDataCallback)dataCallback
                         successCallback:(EMASCurlNetSuccessCallback)successCallback
                            failCallback:(EMASCurlNetFailCallback)failCallback
                        redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback {
    self = [super init];
    if (self) {
        _responseCallback = responseCallback;
        _dataCallback = dataCallback;
        _successCallback = successCallback;
        _failCallback = failCallback;
        _redirectCallback = redirectCallback;
    }
    return self;
}

@end

@interface EMASCurlWebRequestExecutor ()<NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURLSession *URLSession;
@property (nonatomic, strong) NSOperationQueue *requestCallbackQueue;
@property (nonatomic, strong) EMASCurlSafeDictionary *taskToCallbackPackMap;
@property (nonatomic, strong) EMASCurlSafeDictionary *taskidToDataTaskMap;

@end

@implementation EMASCurlWebRequestExecutor

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration {
    if (self = [super init]) {
        sessionConfiguration.HTTPShouldUsePipelining = YES;
        sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        self.URLSession = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                                    delegate:self
                                               delegateQueue:self.requestCallbackQueue];
    }
    return self;
}

- (RequestTaskIdentifier)startWithRequest:(NSURLRequest *)request
                         responseCallback:(EMASCurlNetResponseCallback)responseCallback
                             dataCallback:(EMASCurlNetDataCallback)dataCallback
                          successCallback:(EMASCurlNetSuccessCallback)successCallback
                             failCallback:(EMASCurlNetFailCallback)failCallback
                         redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback {
    NSURLSessionDataTask *dataTask = [self.URLSession dataTaskWithRequest:request];
    EMASCurlWebNetworkCallbackPack *cbPack = [[EMASCurlWebNetworkCallbackPack alloc]
                                               initWithResponseCallback:responseCallback
                                               dataCallback:dataCallback
                                               successCallback:successCallback
                                               failCallback:failCallback
                                               redirectCallback:redirectCallback];

    [self.taskToCallbackPackMap setObject:cbPack forKey:@(dataTask.taskIdentifier)];
    [self.taskidToDataTaskMap setObject:dataTask forKey:@(dataTask.taskIdentifier)];
    [dataTask resume];

    return dataTask.taskIdentifier;
}

- (void)cancelWithRequestIdentifier:(RequestTaskIdentifier)requestTaskIdentifier {
    if (requestTaskIdentifier < 0) {
        return;
    }
    [self.taskToCallbackPackMap removeObjectForKey:@(requestTaskIdentifier)];
    NSURLSessionDataTask *dataTask = [self.taskidToDataTaskMap objectForKey:@(requestTaskIdentifier)];
    if (dataTask) {
        [dataTask cancel];
        [self.taskidToDataTaskMap removeObjectForKey:@(requestTaskIdentifier)];
    }
}

#pragma mark - Lazy

- (NSOperationQueue *)requestCallbackQueue {
    if (!_requestCallbackQueue) {
        _requestCallbackQueue = [NSOperationQueue new];
        _requestCallbackQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        _requestCallbackQueue.maxConcurrentOperationCount = 1;
        _requestCallbackQueue.name = @"com.alicloud.emascurl.networkcallback";
    }
    return _requestCallbackQueue;
}

- (EMASCurlSafeDictionary *)taskToCallbackPackMap {
    if (!_taskToCallbackPackMap) {
        _taskToCallbackPackMap = [EMASCurlSafeDictionary new];
    }
    return _taskToCallbackPackMap;
}

- (EMASCurlSafeDictionary *)taskidToDataTaskMap {
    if (!_taskidToDataTaskMap) {
        _taskidToDataTaskMap = [EMASCurlSafeDictionary new];
    }
    return _taskidToDataTaskMap;
}

#pragma mark - <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

- (void)URLSession:(NSURLSession *)session
              dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSHTTPURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    [self syncCookieToWKWithResponse:response];
    EMASCurlWebNetworkCallbackPack *cbPack = [self.taskToCallbackPackMap objectForKey:@(dataTask.taskIdentifier)];
    if (cbPack && cbPack.responseCallback) {
        cbPack.responseCallback(response);
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    EMASCurlWebNetworkCallbackPack *cbPack = [self.taskToCallbackPackMap objectForKey:@(dataTask.taskIdentifier)];
    if (cbPack && cbPack.dataCallback) {
        cbPack.dataCallback(data);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    EMASCurlWebNetworkCallbackPack *cbPack = [self.taskToCallbackPackMap objectForKey:@(task.taskIdentifier)];
    if (!cbPack) {
        return;
    }
    if (error) {
        if (cbPack.failCallback) {
            cbPack.failCallback(error);
        }
    } else {
        if (cbPack.successCallback) {
            cbPack.successCallback();
        }
    }
    [self.taskToCallbackPackMap removeObjectForKey:@(task.taskIdentifier)];
    [self.taskidToDataTaskMap removeObjectForKey:@(task.taskIdentifier)];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    [self syncCookieToWKWithResponse:response];
    EMASCurlWebNetworkCallbackPack *cbworker = [self.taskToCallbackPackMap objectForKey:@(task.taskIdentifier)];
    void(^redirectDecisionCallback)(BOOL) = ^(BOOL canPass) {
        if (canPass) {
            completionHandler(request);
        } else {
            [task cancel];
            completionHandler(nil);
        }
    };
    if (cbworker && cbworker.redirectCallback) {
        cbworker.redirectCallback(response, request, redirectDecisionCallback);
    } else {
        completionHandler(request);
    }
}

-(void)syncCookieToWKWithResponse:(NSHTTPURLResponse *)response {
    NSArray<NSHTTPCookie *> *responseCookies =
        [NSHTTPCookie cookiesWithResponseHeaderFields:[response allHeaderFields] forURL:response.URL];
    if ([responseCookies isKindOfClass:[NSArray class]] && responseCookies.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [responseCookies enumerateObjectsUsingBlock:^(NSHTTPCookie * _Nonnull cookie, NSUInteger idx, BOOL * _Nonnull stop) {
                if (@available(iOS 11.0, *)) {
                    [[WKWebsiteDataStore defaultDataStore].httpCookieStore setCookie:cookie completionHandler:nil];
                }
            }];
        });
    }
}

@end
