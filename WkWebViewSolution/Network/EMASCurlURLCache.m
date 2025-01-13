//
//  EMASCurlHybridURLCache.m

#import "EMASCurlURLCache.h"
#import <objc/message.h>
#import "EMASCurlCache.h"

@interface EMASCurlURLCache ()
@property (nonatomic, weak) id<EMASCurlURLCacheDelegate> URLCache;
@end

@implementation EMASCurlURLCache

+ (instancetype)defaultCache {
    static EMASCurlURLCache *_defaultCache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _defaultCache = [[EMASCurlURLCache alloc] initWithCacheName:@"hybridURLCache"];
    });
    return _defaultCache;
}

- (instancetype)initWithCacheName:(NSString *)cacheName
{
    self = [super init];
    if (self) {
        _URLCache = [EMASCurlCache shareInstance].netCache;
    }
    return self;
}

- (void)cacheWithHTTPURLResponse:(NSHTTPURLResponse *)response
                            data:(NSData *)data
                             url:(NSString *)url {
    EMASCurlCachedURLResponse *cacheResponse = [[EMASCurlCachedURLResponse alloc] initWithResponse:response data:data];
    if (!cacheResponse.canCache) {
        return;
    }
    [self.URLCache setObject:cacheResponse forKey:url];
}

- (nullable EMASCurlCachedURLResponse *)getCachedResponseWithURL:(NSString *)url {
    EMASCurlCachedURLResponse *cacheResponse = (EMASCurlCachedURLResponse*)[self.URLCache objectForKey:url];
    if (!cacheResponse || ![cacheResponse isKindOfClass:[EMASCurlCachedURLResponse class]]) {
        return nil;
    }
    if ([cacheResponse isExpired]) {
        if (!cacheResponse.etag && !cacheResponse.lastModified) {
            [self.URLCache removeObjectForKey:url];
            return nil;
        }
    }
    return cacheResponse;
}

- (nullable EMASCurlCachedURLResponse *)updateCachedResponseWithURLResponse:(NSHTTPURLResponse *)newResponse
                                                           requestUrl:(NSString *)url{
    EMASCurlCachedURLResponse *cacheResponse = (EMASCurlCachedURLResponse*)[self.URLCache objectForKey:url];
    if (![cacheResponse isKindOfClass:[EMASCurlCachedURLResponse class]]) {
        return nil;
    }
    if (!cacheResponse || ![cacheResponse isKindOfClass:[EMASCurlCachedURLResponse class]]) {
        return nil;
    }
    if (![cacheResponse isExpired]) {
        return cacheResponse;
    }
    EMASCurlCachedURLResponse *toSaveCacheResponse = [cacheResponse copy];
    [toSaveCacheResponse updateWithResponse:newResponse.allHeaderFields];
    if (toSaveCacheResponse.canCache) {
        [self.URLCache setObject:toSaveCacheResponse forKey:url];
    } else {
        [self.URLCache removeObjectForKey:url];
    }
    return toSaveCacheResponse;
}

- (void)clear {
    [self.URLCache removeAllObjects];
}


@end
