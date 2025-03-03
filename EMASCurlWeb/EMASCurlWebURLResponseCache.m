//
//  EMASCurlHybridURLCache.m

#import "EMASCurlWebURLResponseCache.h"
#import "NSCachedURLResponse+EMASCurl.h"
#import <objc/message.h>

@interface EMASCurlWebURLResponseCache ()

@property (nonatomic, strong) NSURLCache *urlCache;

@end

@implementation EMASCurlWebURLResponseCache

- (instancetype)init {
    if (self = [super init]) {
        _urlCache = [NSURLCache sharedURLCache];
    }
    return self;
}

- (void)cacheWithHTTPURLResponse:(NSHTTPURLResponse *)response
                            data:(NSData *)data
                         request:(NSURLRequest *)request {
    if (!request) {
        return;
    }

    NSCachedURLResponse *cachedResponse = [NSCachedURLResponse emas_cachedResponseWithResponse:response
                                                                                         data:data
                                                                                          url:request.URL];

    if (cachedResponse) {
        [self.urlCache storeCachedResponse:cachedResponse forRequest:request];
    }
}

- (nullable NSCachedURLResponse *)getCachedResponseWithRequest:(NSURLRequest *)request {
    if (!request) {
        return nil;
    }

    NSCachedURLResponse *cachedResponse = [self.urlCache cachedResponseForRequest:request];

    if (!cachedResponse) {
        return nil;
    }

    if ([cachedResponse emas_isExpired]) {
        if (![cachedResponse emas_etag] && ![cachedResponse emas_lastModified]) {
            [self.urlCache removeCachedResponseForRequest:request];
            return nil;
        }
    }

    return cachedResponse;
}

- (nullable NSCachedURLResponse *)updateCachedResponseWithURLResponse:(NSHTTPURLResponse *)newResponse
                                                              request:(NSURLRequest *)request {
    if (!request) {
        return nil;
    }

    NSCachedURLResponse *cachedResponse = [self.urlCache cachedResponseForRequest:request];

    if (!cachedResponse) {
        return nil;
    }

    if (![cachedResponse emas_isExpired]) {
        return cachedResponse;
    }

    NSCachedURLResponse *updatedResponse = [cachedResponse emas_updatedResponseWithHeaderFields:newResponse.allHeaderFields];

    if ([updatedResponse emas_canCache]) {
        [self.urlCache storeCachedResponse:updatedResponse forRequest:request];
        return updatedResponse;
    } else {
        [self.urlCache removeCachedResponseForRequest:request];
        return nil;
    }
}

@end
