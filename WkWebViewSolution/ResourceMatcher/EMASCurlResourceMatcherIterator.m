//
//  EMASCurlCacheIterator.m

#import "EMASCurlResourceMatcherIterator.h"
#import "EMASCurlResourceMatcherManager.h"

@implementation EMASCurlResourceMatcherIterator

- (NSArray<id<EMASCurlResourceMatcherImplProtocol>> *)resMatchers {
    NSArray<id<EMASCurlResourceMatcherImplProtocol>> *resMatcherArr = @[];
    if ([self.iteratorDataSource respondsToSelector:@selector(liveResMatchers)]) {
        resMatcherArr = [self.iteratorDataSource liveResMatchers];
     }
   return resMatcherArr;
    
}

- (nullable id<EMASCurlResourceMatcherImplProtocol>)targetMatcherWithUrlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    __block id<EMASCurlResourceMatcherImplProtocol> targetMatcher = nil;
    NSURLRequest *request = urlSchemeTask.request;
    [[self resMatchers] enumerateObjectsUsingBlock:^(id<EMASCurlResourceMatcherImplProtocol>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!obj || ![obj respondsToSelector:@selector(canHandleWithRequest:)]) {
            return;
        }
        if ([obj canHandleWithRequest:request]) {
            targetMatcher = obj;
            *stop = YES;
            return;
        }
    }];
    return targetMatcher;
}

- (void)startWithUrlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    id<EMASCurlResourceMatcherImplProtocol> matcher = [self targetMatcherWithUrlSchemeTask:urlSchemeTask];
    if (!matcher || ![matcher respondsToSelector:@selector(startWithRequest: responseCallback: dataCallback: failCallback: successCallback: redirectCallback:)]) {
        [self.iteratorDelagate didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:nil] urlSchemeTask:urlSchemeTask];
        [self.iteratorDelagate didFinishWithUrlSchemeTask:urlSchemeTask];
        return;
    }
    [matcher startWithRequest:urlSchemeTask.request responseCallback:^(NSURLResponse * _Nonnull response) {
        [self.iteratorDelagate didReceiveResponse:response urlSchemeTask:urlSchemeTask];
    } dataCallback:^(NSData * _Nonnull data) {
        [self.iteratorDelagate didReceiveData:data urlSchemeTask:urlSchemeTask];
    } failCallback:^(NSError * _Nonnull error) {
        [self.iteratorDelagate didFailWithError:error urlSchemeTask:urlSchemeTask];
    } successCallback:^{
        [self.iteratorDelagate didFinishWithUrlSchemeTask:urlSchemeTask];
    } redirectCallback:^(NSURLResponse * _Nonnull response,
                         NSURLRequest * _Nonnull redirectRequest,
                         EMASCurlNetRedirectDecisionCallback  _Nonnull redirectDecisionCallback) {
        [self.iteratorDelagate didRedirectWithResponse:response
                                            newRequest:redirectRequest
                                      redirectDecision:redirectDecisionCallback
                                         urlSchemeTask:urlSchemeTask];
    }];
}

- (void)networkRequestWithUrlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    id<EMASCurlResourceMatcherImplProtocol> networkMatcher = [[self resMatchers] lastObject];
    if (!networkMatcher || ![networkMatcher respondsToSelector:@selector(startWithRequest: responseCallback: dataCallback: failCallback: successCallback: redirectCallback:)]) {
        [self.iteratorDelagate didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:nil] urlSchemeTask:urlSchemeTask];
        [self.iteratorDelagate didFinishWithUrlSchemeTask:urlSchemeTask];
    }
    [networkMatcher startWithRequest:urlSchemeTask.request responseCallback:^(NSURLResponse * _Nonnull response) {
        [self.iteratorDelagate didReceiveResponse:response urlSchemeTask:urlSchemeTask];
    } dataCallback:^(NSData * _Nonnull data) {
        [self.iteratorDelagate didReceiveData:data urlSchemeTask:urlSchemeTask];
    } failCallback:^(NSError * _Nonnull error) {
        [self.iteratorDelagate didFailWithError:error urlSchemeTask:urlSchemeTask];
    } successCallback:^{
        [self.iteratorDelagate didFinishWithUrlSchemeTask:urlSchemeTask];
    } redirectCallback:^(NSURLResponse * _Nonnull response,
                         NSURLRequest * _Nonnull redirectRequest,
                         EMASCurlNetRedirectDecisionCallback  _Nonnull redirectDecisionCallback) {
        [self.iteratorDelagate didRedirectWithResponse:response
                                            newRequest:redirectRequest
                                      redirectDecision:redirectDecisionCallback
                                         urlSchemeTask:urlSchemeTask];
    }];
}

@end
