//
//  EMASCurlSchemeHandleManager.m

#import "EMASCurlResourceMatcherManager.h"
#import "EMASCurlUtils.h"
#import "EMASCurlNetworkResourceMatcher.h"
#import "EMASCurlResourceMatcherIterator.h"
#import <os/lock.h>
#import "EMASCurlUtils.h"

@interface EMASCurlResourceMatcherManager ()<EMASCurlResourceMatcherIteratorProtocol, EMASCurlResourceMatcherIteratorDataSource>

@property(nonatomic, strong) EMASCurlResourceMatcherIterator *iterator;

@property(nonatomic, strong) EMASCurlNetworkResourceMatcher *defaultNetworkResourceMatcher;

@end

@implementation EMASCurlResourceMatcherManager{
    os_unfair_lock _taskMaplock;
    NSHashTable *_taskHashTable;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _taskMaplock = OS_UNFAIR_LOCK_INIT;
        _taskHashTable = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

#pragma mark - WKURLSchemeHandler
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask API_AVAILABLE(ios(LimitVersion)){
    os_unfair_lock_lock(&_taskMaplock);
    [_taskHashTable addObject:urlSchemeTask];
    os_unfair_lock_unlock(&_taskMaplock);
    
    EMASCurlCacheLog(@"Hybrid拦截到，url: %@", urlSchemeTask.request.URL.absoluteString);
    [self.iterator startWithUrlSchemeTask:urlSchemeTask];
}


- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask API_AVAILABLE(ios(LimitVersion)){
    os_unfair_lock_lock(&_taskMaplock);
    [_taskHashTable removeObject:urlSchemeTask];
    os_unfair_lock_unlock(&_taskMaplock);
}

#pragma mark - EMASCurlResourceMatcherIteratorProtocol
- (void)didReceiveResponse:(NSURLResponse *)response urlSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask {
    if (![self isAliveWithURLSchemeTask:urlSchemeTask]) {
        return;
    }
    @try {
        EMASCurlCacheLog(@"Hybrid返回response，url: %@", urlSchemeTask.request.URL.absoluteString);
        [urlSchemeTask didReceiveResponse:response];
    } @catch (NSException *exception) {} @finally {}
}

- (void)didReceiveData:(NSData *)data urlSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask{
    if (![self isAliveWithURLSchemeTask:urlSchemeTask]) {
        return;
    }
    @try {
        EMASCurlCacheLog(@"Hybrid返回data，length: %ld, url: %@", data.length, urlSchemeTask.request.URL.absoluteString);
        [urlSchemeTask didReceiveData:data];
    } @catch (NSException *exception) {} @finally {}
}

- (void)didFinishWithUrlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask{
    if (![self isAliveWithURLSchemeTask:urlSchemeTask]) {
        return;
    }
    @try {
        EMASCurlCacheLog(@"Hybrid返回Finish，url: %@", urlSchemeTask.request.URL.absoluteString);
        [urlSchemeTask didFinish];
    } @catch (NSException *exception) {} @finally {}
}

- (void)didFailWithError:(NSError *)error urlSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask{
    if (![self isAliveWithURLSchemeTask:urlSchemeTask]) {
        return;
    }
    @try {
        EMASCurlCacheLog(@"Hybrid返回error，url: %@", urlSchemeTask.request.URL.absoluteString);
        [urlSchemeTask didFailWithError:error];
    } @catch (NSException *exception) {} @finally {}
}

- (void)didRedirectWithResponse:(NSURLResponse *)response newRequest:(NSURLRequest *)redirectRequest redirectDecision:(EMASCurlNetRedirectDecisionCallback)redirectDecisionCallback urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    if (![EMASCurlUtils isEqualURLA:urlSchemeTask.request.mainDocumentURL.absoluteString withURLB:response.URL.absoluteString]) {
        redirectDecisionCallback(YES);
        return;
    }
    redirectDecisionCallback(NO);
    if ([self isAliveWithURLSchemeTask:urlSchemeTask]){
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

#pragma mark - EMASCurlResourceMatcherIteratorDataSource
- (nonnull NSArray<id<EMASCurlResourceMatcherImplProtocol>> *)liveResMatchers {
    NSMutableArray *matchersM = [NSMutableArray arrayWithCapacity:0];
    if ([self.delegate respondsToSelector:@selector(liveMatchers)]) {
        NSArray *customMatchers = [self.delegate liveMatchers];
        if (EMASCurlValidArr(customMatchers)) {
            [matchersM addObjectsFromArray:customMatchers];
        }
    }
    [matchersM addObject:self.defaultNetworkResourceMatcher];
    return [matchersM copy];
}


// 判断urlSchemeTask是否被释放
- (BOOL)isAliveWithURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    BOOL urlSchemeTaskAlive = NO;
    @try {
        os_unfair_lock_lock(&_taskMaplock);
        urlSchemeTaskAlive = [_taskHashTable containsObject:urlSchemeTask];
        os_unfair_lock_unlock(&_taskMaplock);
    } @catch (NSException *exception) {
        EMASCurlCacheLog(@"isAliveWithURLSchemeTask 执行异常");
    } @finally {}
    return urlSchemeTaskAlive;
}

- (void)redirectWithRequest:(NSURLRequest *)redirectRequest {
    if ([self.delegate respondsToSelector:@selector(redirectWithRequest:)]) {
        [self.delegate redirectWithRequest:redirectRequest];
    }
}

- (EMASCurlResourceMatcherIterator *)iterator {
    if (!_iterator) {
        _iterator = [[EMASCurlResourceMatcherIterator alloc] init];
        _iterator.iteratorDelagate = self;
        _iterator.iteratorDataSource = self;
    }
    return _iterator;
}

- (EMASCurlNetworkResourceMatcher *)defaultNetworkResourceMatcher {
    if (!_defaultNetworkResourceMatcher) {
        _defaultNetworkResourceMatcher = [EMASCurlNetworkResourceMatcher new];
    }
    return _defaultNetworkResourceMatcher;
}

@end
