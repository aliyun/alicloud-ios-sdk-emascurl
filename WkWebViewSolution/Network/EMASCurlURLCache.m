//
//  EMASCurlHybridURLCache.m
//  EMASCurlBHybridModule
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
