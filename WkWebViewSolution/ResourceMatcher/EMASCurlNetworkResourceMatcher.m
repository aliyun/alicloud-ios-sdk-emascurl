//
//  EMASCurlNetworkResourceMatcher.m
//  EMASCurlHybrid
/*
 MIT License

Copyright (c) 2022 EMASCurl.com, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

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
