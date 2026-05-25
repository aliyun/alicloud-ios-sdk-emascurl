//
//  EMASCurlResponseCache.m
//  EMASCurl
//
//  Created by xuyecan on 2025/5/12.
//

#import "EMASCurlResponseCache.h"
#import "NSCachedURLResponse+EMASCurl.h"
#import "EMASCurlLogger.h"

@interface EMASCurlResponseCache ()

@property (nonatomic, strong) NSURLCache *urlCache;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;

@end

@implementation EMASCurlResponseCache

static NSDictionary<NSString *, NSString *> *EMASCacheImmutableHTTPHeaderFields(NSDictionary *headers) {
    if (headers.count == 0) {
        return @{};
    }

    NSMutableDictionary<NSString *, NSString *> *immutableHeaders = [NSMutableDictionary dictionaryWithCapacity:headers.count];
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSString class]]) {
            return;
        }
        immutableHeaders[[key copy]] = [obj copy];
    }];
    return [immutableHeaders copy];
}

static NSURLResponse *EMASCacheImmutableResponse(NSURLResponse *response, NSDictionary *userInfo) {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return response;
    }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSString *httpVersion = [userInfo[EMASUserInfoKeyOriginalHTTPVersion] isKindOfClass:[NSString class]] ? userInfo[EMASUserInfoKeyOriginalHTTPVersion] : @"HTTP/1.1";
    return [[NSHTTPURLResponse alloc] initWithURL:httpResponse.URL
                                      statusCode:httpResponse.statusCode
                                     HTTPVersion:httpVersion
                                    headerFields:EMASCacheImmutableHTTPHeaderFields(httpResponse.allHeaderFields)] ?: response;
}

static NSData *EMASCacheImmutableData(NSData *data) {
    if (!data) {
        return [NSData data];
    }
    return [data isKindOfClass:[NSMutableData class]] ? [data copy] : data;
}

- (instancetype)init {
    if (self = [super init]) {
        _urlCache = [NSURLCache sharedURLCache];
        _cacheQueue = dispatch_queue_create("com.alicloud.emascurl.cacheQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)cacheResponse:(NSHTTPURLResponse *)response
                 data:(NSData *)data
           forRequest:(NSURLRequest *)request
      withHTTPVersion:(NSString *)httpVersion {
    if (!request || !response || !data) {
        EMAS_LOG_ERROR(@"EC-Cache", @"Failed to cache response: nil request, response, or data");
        return;
    }

    dispatch_sync(self.cacheQueue, ^{
        // 使用类别方法创建并检查是否可缓存
        // request.URL 用于NSCachedURLResponse初始化，因为response.URL可能因重定向而与原始请求URL不同
        NSCachedURLResponse *emasCachedResponse = [NSCachedURLResponse emas_cachedResponseWithHTTPURLResponse:response
                                                                                                        data:data
                                                                                                  requestURL:request.URL
                                                                                                 httpVersion:httpVersion
                                                                                             originalRequest:request];

        if (emasCachedResponse) {
            emasCachedResponse = [self sanitizedResponseForStorage:emasCachedResponse
                                                             stage:@"cacheResponse.beforeStore"
                                                           request:request];
            EMAS_LOG_DEBUG(@"EC-Cache", @"Storing response in cache for URL: %@", request.URL.absoluteString);
            [self.urlCache storeCachedResponse:emasCachedResponse forRequest:request];
        } else {
            EMAS_LOG_DEBUG(@"EC-Cache", @"Response not cacheable for URL: %@", request.URL.absoluteString);
        }
    });
}

- (nullable NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request {
    if (!request) {
        return nil;
    }

    __block NSCachedURLResponse *result = nil;
    dispatch_sync(self.cacheQueue, ^{
        NSCachedURLResponse *cachedResponse = [self.urlCache cachedResponseForRequest:request];

        if (!cachedResponse) {
            EMAS_LOG_DEBUG(@"EC-Cache", @"No cached response found for URL: %@", request.URL.absoluteString);
            return;
        }

        // 检查是否是 NSHTTPURLResponse，我们的类别方法依赖这个
        if (![cachedResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
            [self.urlCache removeCachedResponseForRequest:request];
            return;
        }

        // 验证Vary头匹配
        if (![cachedResponse emas_matchesVaryHeadersForRequest:request]) {
            // Vary头不匹配，视为缓存未命中（不移除，可能有其他变体适用）
            EMAS_LOG_DEBUG(@"EC-Cache", @"Vary header mismatch for URL: %@", request.URL.absoluteString);
            return;
        }

        // 如果响应已过期且没有验证器 (ETag 或 Last-Modified)，则移除并返回nil
        // emas_isResponseStillFreshForRequest 也会检查请求的 no-cache 等指令
        BOOL isFresh = [cachedResponse emas_isResponseStillFreshForRequest:request];
        BOOL requiresRevalidation = [cachedResponse emas_requiresRevalidation]; // 例如 Cache-Control: no-cache

        if (isFresh && !requiresRevalidation) {
            result = cachedResponse; // 响应是新鲜的且不需要重新验证
            return;
        }

        // 到这里，响应要么是陈旧的，要么是新鲜但需要重新验证 (no-cache)
        // 我们需要检查它是否有验证器 (ETag/Last-Modified)
        if ([cachedResponse emas_etag] || [cachedResponse emas_lastModified]) {
            result = cachedResponse; // 可以用于条件请求
            return;
        }

        // 陈旧/需要验证，但没有验证器，则此缓存无用
        [self.urlCache removeCachedResponseForRequest:request];
    });

    return result;
}

- (nullable NSCachedURLResponse *)updateCachedResponseWithHeaders:(NSDictionary *)newResponseHeaders
                                                       forRequest:(NSURLRequest *)request {
    if (!request || !newResponseHeaders) {
        return nil;
    }

    __block NSCachedURLResponse *result = nil;
    dispatch_sync(self.cacheQueue, ^{
        NSCachedURLResponse *oldCachedResponse = [self.urlCache cachedResponseForRequest:request];

        if (!oldCachedResponse) {
            return;
        }

        if (![oldCachedResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
            EMAS_LOG_INFO(@"EC-Cache", @"Invalid cached response type during 304 update for URL: %@", request.URL.absoluteString);
            [self.urlCache removeCachedResponseForRequest:request];
            return;
        }

        // 使用类别方法更新响应头
        NSCachedURLResponse *updatedCachedResponse = [oldCachedResponse emas_updatedResponseWithHeadersFrom304Response:newResponseHeaders];

        // 再次检查更新后的响应是否仍然可缓存 (虽然通常304更新的是元数据，不改变可缓存性)
        // 实际上，emas_updatedResponseWithHeadersFrom304Response 已经创建了一个有效的NSCachedURLResponse
        // 我们只需存储它
        if (updatedCachedResponse) {
            updatedCachedResponse = [self sanitizedResponseForStorage:updatedCachedResponse
                                                               stage:@"updateCachedResponse.beforeStore"
                                                             request:request];
            [self.urlCache storeCachedResponse:updatedCachedResponse forRequest:request];
            result = updatedCachedResponse;
        } else {
            // 理论上不应该发生，除非emas_updatedResponseWithHeadersFrom304Response实现问题
            // 保险起见，移除旧的，因为它可能已损坏或无法正确更新
            [self.urlCache removeCachedResponseForRequest:request];
        }
    });

    return result;
}

- (NSCachedURLResponse *)sanitizedResponseForStorage:(NSCachedURLResponse *)cachedResponse
                                               stage:(NSString *)stage
                                             request:(NSURLRequest *)request {
    if (!cachedResponse) {
        return nil;
    }

    NSData *immutableData = EMASCacheImmutableData(cachedResponse.data);
    NSDictionary *userInfo = cachedResponse.userInfo;
    NSDictionary *immutableUserInfo = nil;

    if (userInfo) {
        NSError *error = nil;
        NSData *plistData = nil;
        @try {
            plistData = [NSPropertyListSerialization dataWithPropertyList:userInfo
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                                  options:0
                                                                    error:&error];
            if (plistData) {
                id plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                                     options:NSPropertyListImmutable
                                                                      format:nil
                                                                       error:&error];
                if ([plist isKindOfClass:[NSDictionary class]]) {
                    immutableUserInfo = plist;
                }
            }
        } @catch (NSException *exception) {
            error = [NSError errorWithDomain:@"EMASCurlResponseCache"
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name ?: @"property list exception"}];
        }

        if (!immutableUserInfo) {
            EMAS_LOG_INFO(@"EC-Cache",
                          @"[%@] dropping invalid cachedResponse.userInfo before store. url=%@ error=%@",
                          stage,
                          request.URL.absoluteString ?: @"(null)",
                          error.localizedDescription ?: @"(unknown)");
        }
    }

    NSURLResponse *immutableResponse = EMASCacheImmutableResponse(cachedResponse.response, immutableUserInfo ?: userInfo);
    return [[NSCachedURLResponse alloc] initWithResponse:immutableResponse
                                                    data:immutableData
                                                userInfo:immutableUserInfo
                                           storagePolicy:cachedResponse.storagePolicy];
}

@end
