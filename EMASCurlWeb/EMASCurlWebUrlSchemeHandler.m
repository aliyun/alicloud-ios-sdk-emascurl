//
//  EMASCurlUrlSchemeHandler.m
//  EMASCurl
//
//  Created by xuyecan on 2025/2/3.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>
#import "EMASCurlWebUtils.h"
#import "EMASCurlWebNetworkManager.h"
#import "EMASCurlWebUrlSchemeHandler.h"
#import "WKWebViewConfiguration+Loader.h"
#import "EMASCurlWebLogger.h"

@protocol EMASCurlResourceMatcherManagerDelegate <NSObject>

- (void)redirectWithRequest:(NSURLRequest *)redirectRequest;

@end

@interface EMASCurlWebUrlSchemeHandler () {
    os_unfair_lock _taskMaplock;
    NSHashTable *_taskHashTable;
}

@property (nonatomic, strong) EMASCurlWebNetworkManager *networkSession;

@end

@implementation EMASCurlWebUrlSchemeHandler

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    self = [super init];
    if (self) {
        _taskMaplock = OS_UNFAIR_LOCK_INIT;
        _taskHashTable = [NSHashTable weakObjectsHashTable];

        _networkSession = [[EMASCurlWebNetworkManager alloc] initWithSessionConfiguration:configuration];
    }
    return self;
}

- (void)dealloc {
    [_networkSession cancelAllTasks];
}

#pragma mark - Network Resource Matcher Methods

- (BOOL)canHandleWithRequest:(NSURLRequest *)request {
    return YES;
}

- (void)startWithRequest:(NSURLRequest *)request
         responseCallback:(EMASCurlNetResponseCallback)responseCallback
             dataCallback:(EMASCurlNetDataCallback)dataCallback
             failCallback:(EMASCurlNetFailCallback)failCallback
          successCallback:(EMASCurlNetSuccessCallback)successCallback
         redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback {

    EMASCurlNetworkDataTask *dataTask = [self.networkSession dataTaskWithRequest:request
                                                                responseCallback:responseCallback
                                                                    dataCallback:dataCallback
                                                                 successCallback:^{
        successCallback();
        EMASCurlCacheLog(@"WebContentLoader fetched data from network, url: %@", request.URL.absoluteString);
    }
                                                                    failCallback:failCallback
                                                                redirectCallback:redirectCallback];
    [dataTask resume];
}

#pragma mark - WKURLSchemeHandler

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask API_AVAILABLE(ios(LimitVersion)) {
    os_unfair_lock_lock(&_taskMaplock);
    [_taskHashTable addObject:urlSchemeTask];
    os_unfair_lock_unlock(&_taskMaplock);

    EMASCurlCacheLog(@"WebContentLoader intercepted url: %@", urlSchemeTask.request.URL.absoluteString);

    EMASCurlWeak(self)
    [self startWithRequest:urlSchemeTask.request
         responseCallback:^(NSURLResponse * _Nonnull response) {
             EMASCurlStrong(self)
             [self didReceiveResponse:response urlSchemeTask:urlSchemeTask];
         }
             dataCallback:^(NSData * _Nonnull data) {
             EMASCurlStrong(self)
             [self didReceiveData:data urlSchemeTask:urlSchemeTask];
         }
             failCallback:^(NSError * _Nonnull error) {
             EMASCurlStrong(self)
             [self didFailWithError:error urlSchemeTask:urlSchemeTask];
         }
          successCallback:^{
             EMASCurlStrong(self)
             [self didFinishWithUrlSchemeTask:urlSchemeTask];
         }
         redirectCallback:^(NSURLResponse * _Nonnull response, NSURLRequest * _Nonnull redirectRequest, EMASCurlNetRedirectDecisionCallback redirectDecisionCallback) {
             EMASCurlStrong(self)
             [self didRedirectWithResponse:response newRequest:redirectRequest redirectDecision:redirectDecisionCallback urlSchemeTask:urlSchemeTask];
         }];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask API_AVAILABLE(ios(LimitVersion)) {
    os_unfair_lock_lock(&_taskMaplock);
    [_taskHashTable removeObject:urlSchemeTask];
    os_unfair_lock_unlock(&_taskMaplock);
}

#pragma mark - Task Callbacks

- (void)didReceiveResponse:(NSURLResponse *)response urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    if (![self isAliveWithURLSchemeTask:urlSchemeTask]) {
        return;
    }
    @try {
        EMASCurlCacheLog(@"WebContentLoader received response, url: %@", urlSchemeTask.request.URL.absoluteString);
        [urlSchemeTask didReceiveResponse:response];
    } @catch (NSException *exception) {} @finally {}
}

- (void)didReceiveData:(NSData *)data urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    if (![self isAliveWithURLSchemeTask:urlSchemeTask]) {
        return;
    }
    @try {
        EMASCurlCacheLog(@"WebContentLoader received data, length: %ld, url: %@", data.length, urlSchemeTask.request.URL.absoluteString);
        [urlSchemeTask didReceiveData:data];
    } @catch (NSException *exception) {} @finally {}
}

- (void)didFinishWithUrlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    if (![self isAliveWithURLSchemeTask:urlSchemeTask]) {
        return;
    }
    @try {
        EMASCurlCacheLog(@"WebContentLoader finished, url: %@", urlSchemeTask.request.URL.absoluteString);
        [urlSchemeTask didFinish];
    } @catch (NSException *exception) {} @finally {}
}

- (void)didFailWithError:(NSError *)error urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    if (![self isAliveWithURLSchemeTask:urlSchemeTask]) {
        return;
    }
    @try {
        EMASCurlCacheLog(@"WebContentLoader encountered error, url: %@", urlSchemeTask.request.URL.absoluteString);
        [urlSchemeTask didFailWithError:error];
    } @catch (NSException *exception) {} @finally {}
}

- (void)didRedirectWithResponse:(NSURLResponse *)response
                     newRequest:(NSURLRequest *)redirectRequest
               redirectDecision:(EMASCurlNetRedirectDecisionCallback)redirectDecisionCallback
                  urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    if (![EMASCurlWebUtils isEqualURLA:urlSchemeTask.request.mainDocumentURL.absoluteString withURLB:response.URL.absoluteString]) {
        redirectDecisionCallback(YES);
        return;
    }
    redirectDecisionCallback(NO);
    if ([self isAliveWithURLSchemeTask:urlSchemeTask]) {
        NSString *s1 = @"didPerform";
        NSString *s2 = @"Redirection:";
        NSString *s3 = @"newRequest:";
        SEL sel = NSSelectorFromString([NSString stringWithFormat:@"_%@%@%@", s1, s2, s3]);
        if ([urlSchemeTask respondsToSelector:sel]) {
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [urlSchemeTask performSelector:sel withObject:response withObject:redirectRequest];
#pragma clang diagnostic pop
            } @catch (NSException *exception) {
            } @finally {}
        }
    }
    [self redirectWithRequest:redirectRequest];
}

#pragma mark - Utility Methods

- (BOOL)isAliveWithURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    BOOL alive = NO;
    os_unfair_lock_lock(&_taskMaplock);
    alive = [_taskHashTable containsObject:urlSchemeTask];
    os_unfair_lock_unlock(&_taskMaplock);
    EMASCurlCacheLog(@"isAliveWithURLSchemeTask encountered an exception");
    return alive;
}

- (void)redirectWithRequest:(NSURLRequest *)redirectRequest {
    void *storeKey = (__bridge  void*)[EMASCurlWebUrlSchemeHandler class];
    EMASCurlWebWeakProxy *redirectDelegateProxy = objc_getAssociatedObject(self, storeKey);
    if ([redirectDelegateProxy respondsToSelector:@selector(redirectWithRequest:)]) {
        ((void (*)(id, SEL, NSURLRequest *))objc_msgSend)(redirectDelegateProxy, @selector(redirectWithRequest:), redirectRequest);
    }
}

@end
