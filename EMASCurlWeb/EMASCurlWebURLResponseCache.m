//
//  EMASCurlHybridURLCache.m

#import "EMASCurlWebURLResponseCache.h"
#import <objc/message.h>

@interface EMASCurlWebURLResponseCache ()
@property (nonatomic, weak) id<EMASCurlWebCacheProtocol> cacheDelegate;
@end

@implementation EMASCurlWebURLResponseCache

- (instancetype)initWithDelegate:(id<EMASCurlWebCacheProtocol>)delegate {
    if (self = [super init]) {
        _cacheDelegate = delegate;
    }
    return self;
}

- (void)cacheWithHTTPURLResponse:(NSHTTPURLResponse *)response
                            data:(NSData *)data
                             url:(NSString *)url {
    EMASCurlWebURLResponse *cacheResponse = [[EMASCurlWebURLResponse alloc] initWithResponse:response data:data];
    if (!cacheResponse.canCache) {
        return;
    }
    [self.cacheDelegate setObject:cacheResponse forKey:url];
}

- (nullable EMASCurlWebURLResponse *)getCachedResponseWithURL:(NSString *)url {
    EMASCurlWebURLResponse *cacheResponse = (EMASCurlWebURLResponse*)[self.cacheDelegate objectForKey:url];
    if (!cacheResponse || ![cacheResponse isKindOfClass:[EMASCurlWebURLResponse class]]) {
        return nil;
    }
    if ([cacheResponse isExpired]) {
        if (!cacheResponse.etag && !cacheResponse.lastModified) {
            [self.cacheDelegate removeObjectForKey:url];
            return nil;
        }
    }
    return cacheResponse;
}

- (nullable EMASCurlWebURLResponse *)updateCachedResponseWithURLResponse:(NSHTTPURLResponse *)newResponse
                                                           requestUrl:(NSString *)url {
    EMASCurlWebURLResponse *cacheResponse = (EMASCurlWebURLResponse*)[self.cacheDelegate objectForKey:url];
    if (![cacheResponse isKindOfClass:[EMASCurlWebURLResponse class]]) {
        return nil;
    }
    if (!cacheResponse || ![cacheResponse isKindOfClass:[EMASCurlWebURLResponse class]]) {
        return nil;
    }
    if (![cacheResponse isExpired]) {
        return cacheResponse;
    }
    EMASCurlWebURLResponse *toSaveCacheResponse = [cacheResponse copy];
    [toSaveCacheResponse updateWithResponse:newResponse.allHeaderFields];
    if (toSaveCacheResponse.canCache) {
        [self.cacheDelegate setObject:toSaveCacheResponse forKey:url];
    } else {
        [self.cacheDelegate removeObjectForKey:url];
    }
    return toSaveCacheResponse;
}

- (void)clear {
    [self.cacheDelegate removeAllObjects];
}


@end
