#import "NSCachedURLResponse+EMASCurl.h"
#import "EMASCurlWebUtils.h"

@implementation NSCachedURLResponse (EMASCurl)

#pragma mark - Public Methods

- (BOOL)emas_canCache {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return NO;
    }

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;

    // 检查状态码
    if (httpResponse.statusCode != 200) {
        return NO;
    }

    // 检查 Content-Type
    NSString *contentType = httpResponse.allHeaderFields[@"Content-Type"];
    if (!EMASCurlValidStr(contentType)) {
        return NO;
    }

    if ([contentType containsString:@"text/html"] || [contentType containsString:@"video"]) {
        return NO;
    }

    // 检查 Cache-Control
    NSString *cacheControl = httpResponse.allHeaderFields[@"Cache-Control"];
    if (!EMASCurlValidStr(cacheControl)) {
        return NO;
    }

    NSArray<NSString *> *controlItems = [cacheControl componentsSeparatedByString:@","];
    BOOL shouldCache = NO;

    for (NSString *item in controlItems) {
        NSString *trimmedItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmedItem isEqualToString:@"no-cache"] || [trimmedItem isEqualToString:@"no-store"]) {
            return NO;
        }

        if ([trimmedItem hasPrefix:@"max-age"] && trimmedItem.length > 8) {
            long long age = [[trimmedItem substringFromIndex:8] longLongValue];
            if (age > 0) {
                shouldCache = YES;
            }
        }
    }

    return shouldCache;
}

- (BOOL)emas_isExpired {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return YES;
    }

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
    NSTimeInterval maxAge = [self emas_maxAgeFromResponse:httpResponse];
    NSTimeInterval timestamp = [self.userInfo[@"timestamp"] doubleValue];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;

    return (now - timestamp) >= maxAge;
}

- (nullable NSString *)emas_etag {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return nil;
    }

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
    NSString *etag = httpResponse.allHeaderFields[@"Etag"];

    return EMASCurlValidStr(etag) ? etag : nil;
}

- (nullable NSString *)emas_lastModified {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return nil;
    }

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
    NSString *lastModified = httpResponse.allHeaderFields[@"Last-Modified"];

    return EMASCurlValidStr(lastModified) ? lastModified : nil;
}

- (NSCachedURLResponse *)emas_updatedResponseWithHeaderFields:(NSDictionary *)newHeaderFields {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return self;
    }

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
    NSMutableDictionary *headerFields = [httpResponse.allHeaderFields mutableCopy];

    [newHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        if (!EMASCurlValidStr(key) || !EMASCurlValidStr(value)) {
            return;
        }
        NSString *oldValue = httpResponse.allHeaderFields[key];
        if (!EMASCurlValidStr(oldValue)) {
            return;
        }
        headerFields[key] = value;
    }];

    NSHTTPURLResponse *updatedResponse = [[NSHTTPURLResponse alloc]
                                         initWithURL:httpResponse.URL
                                         statusCode:httpResponse.statusCode
                                         HTTPVersion:@"HTTP/2"
                                         headerFields:[headerFields copy]];

    // 更新时间戳
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:self.userInfo];
    userInfo[@"timestamp"] = @([NSDate date].timeIntervalSince1970);

    return [[NSCachedURLResponse alloc] initWithResponse:updatedResponse
                                                   data:self.data
                                               userInfo:userInfo
                                          storagePolicy:self.storagePolicy];
}

+ (nullable NSCachedURLResponse *)emas_cachedResponseWithResponse:(NSHTTPURLResponse *)response
                                                            data:(NSData *)data
                                                            url:(NSURL *)url {
    // 创建一个临时缓存响应以检查是否可以缓存
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[@"timestamp"] = @([NSDate date].timeIntervalSince1970);

    NSCachedURLResponse *cachedResponse = [[NSCachedURLResponse alloc]
                                          initWithResponse:response
                                                     data:data
                                                 userInfo:userInfo
                                            storagePolicy:NSURLCacheStorageAllowed];

    if (![cachedResponse emas_canCache]) {
        return nil;
    }

    return cachedResponse;
}

#pragma mark - Private Helper Methods

- (NSTimeInterval)emas_maxAgeFromResponse:(NSHTTPURLResponse *)response {
    NSString *cacheControl = response.allHeaderFields[@"Cache-Control"];
    if (!EMASCurlValidStr(cacheControl)) {
        return 0;
    }

    NSArray<NSString *> *controlItems = [cacheControl componentsSeparatedByString:@","];

    for (NSString *item in controlItems) {
        NSString *trimmedItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmedItem hasPrefix:@"max-age"] && trimmedItem.length > 8) {
            return [[trimmedItem substringFromIndex:8] longLongValue];
        }
    }

    return 0;
}

@end
