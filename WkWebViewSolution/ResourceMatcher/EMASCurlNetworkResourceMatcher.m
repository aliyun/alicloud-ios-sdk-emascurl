//
//  EMASCurlNetworkResourceMatcher.m

#import "EMASCurlNetworkResourceMatcher.h"
#import "EMASCurlNetworkSession.h"
#import "EMASCurlUtils.h"

@interface EMASCurlNetworkResourceMatcher ()
@property (nonatomic, strong) EMASCurlNetworkSession *networkSession;
@end

@implementation EMASCurlNetworkResourceMatcher

- (BOOL)canHandleWithRequest:(nonnull NSURLRequest *)request {
    return YES;
}

- (void)startWithRequest:(nonnull NSURLRequest *)request
        responseCallback:(nonnull EMASCurlNetResponseCallback)responseCallback
            dataCallback:(nonnull EMASCurlNetDataCallback)dataCallback
            failCallback:(nonnull EMASCurlNetFailCallback)failCallback
         successCallback:(nonnull EMASCurlNetSuccessCallback)successCallback
        redirectCallback:(nonnull EMASCurlNetRedirectCallback)redirectCallback{
    EMASCurlNetworkDataTask *dataTask = [self.networkSession dataTaskWithRequest:request
                                                          responseCallback:responseCallback
                                                              dataCallback:dataCallback
                                                           successCallback:^{
        successCallback();
        EMASCurlCacheLog(@"从网络请求获取数据，url: %@", request.URL.absoluteString);
    }
                                                              failCallback:failCallback
                                                          redirectCallback:redirectCallback];
    [dataTask resume];
}


- (void)dealloc {
    [_networkSession cancelAllTasks];
}

#pragma mark - lazy

- (EMASCurlNetworkSession *)networkSession {
    if (!_networkSession) {
        _networkSession = [EMASCurlNetworkSession sessionWithConfiguation:[EMASCurlNetworkSessionConfiguration new]];
    }
    return _networkSession;
}

@end
