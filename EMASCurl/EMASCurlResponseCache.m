//
//  EMASCurlResponseCache.m
//  EMASCurl
//
//  Created by xuyecan on 2025/5/12.
//

#import "EMASCurlResponseCache.h"
#import "NSCachedURLResponse+EMASCurl.h"

@interface EMASCurlResponseCache ()

@property (nonatomic, strong) NSURLCache *urlCache;

@end

@implementation EMASCurlResponseCache

- (instancetype)init {
    if (self = [super init]) {
        _urlCache = [NSURLCache sharedURLCache];
    }
    return self;
}

- (void)cacheResponse:(NSHTTPURLResponse *)response
                 data:(NSData *)data
           forRequest:(NSURLRequest *)request
      withHTTPVersion:(NSString *)httpVersion {
    if (!request || !response || !data) {
        NSLog(@"[Cache] Attempted to cache with nil request, response, or data.");
        return;
    }

    // 使用类别方法创建并检查是否可缓存
    // request.URL 用于NSCachedURLResponse初始化，因为response.URL可能因重定向而与原始请求URL不同
    NSCachedURLResponse *emasCachedResponse = [NSCachedURLResponse emas_cachedResponseWithHTTPURLResponse:response
                                                                                                    data:data
                                                                                              requestURL:request.URL
                                                                                             httpVersion:httpVersion];

    if (emasCachedResponse) {
        [self.urlCache storeCachedResponse:emasCachedResponse forRequest:request];
    }
}

- (nullable NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request {
    if (!request) {
        return nil;
    }

    NSCachedURLResponse *cachedResponse = [self.urlCache cachedResponseForRequest:request];

    if (!cachedResponse) {
        return nil;
    }

    // 检查是否是 NSHTTPURLResponse，我们的类别方法依赖这个
    if (![cachedResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        [self.urlCache removeCachedResponseForRequest:request];
        return nil;
    }

    // 如果响应已过期且没有验证器 (ETag 或 Last-Modified)，则移除并返回nil
    // emas_isResponseStillFreshForRequest 也会检查请求的 no-cache 等指令
    BOOL isFresh = [cachedResponse emas_isResponseStillFreshForRequest:request];
    BOOL requiresRevalidation = [cachedResponse emas_requiresRevalidation]; // 例如 Cache-Control: no-cache

    if (isFresh && !requiresRevalidation) {
        return cachedResponse; // 响应是新鲜的且不需要重新验证
    }

    // 到这里，响应要么是陈旧的，要么是新鲜但需要重新验证 (no-cache)
    // 我们需要检查它是否有验证器 (ETag/Last-Modified)
    if ([cachedResponse emas_etag] || [cachedResponse emas_lastModified]) {
        return cachedResponse; // 可以用于条件请求
    }

    // 陈旧/需要验证，但没有验证器，则此缓存无用
    [self.urlCache removeCachedResponseForRequest:request];
    return nil;
}

- (nullable NSCachedURLResponse *)updateCachedResponseWithHeaders:(NSDictionary *)newResponseHeaders
                                                       forRequest:(NSURLRequest *)request {
    if (!request || !newResponseHeaders) {
        return nil;
    }

    NSCachedURLResponse *oldCachedResponse = [self.urlCache cachedResponseForRequest:request];

    if (!oldCachedResponse) {
        return nil;
    }

    // 使用类别方法更新响应头
    NSCachedURLResponse *updatedCachedResponse = [oldCachedResponse emas_updatedResponseWithHeadersFrom304Response:newResponseHeaders];

    // 再次检查更新后的响应是否仍然可缓存 (虽然通常304更新的是元数据，不改变可缓存性)
    // 实际上，emas_updatedResponseWithHeadersFrom304Response 已经创建了一个有效的NSCachedURLResponse
    // 我们只需存储它
    if (updatedCachedResponse) {
        [self.urlCache storeCachedResponse:updatedCachedResponse forRequest:request];
        return updatedCachedResponse;
    } else {
        // 理论上不应该发生，除非emas_updatedResponseWithHeadersFrom304Response实现问题
        // 保险起见，移除旧的，因为它可能已损坏或无法正确更新
        [self.urlCache removeCachedResponseForRequest:request];
        return nil;
    }
}

@end
