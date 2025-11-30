//
//  NSCachedURLResponse+EMASCurl.m
//  EMASCurl
//
//  Created by xuyecan on 2025/5/12.
//

#import "NSCachedURLResponse+EMASCurl.h"

@implementation NSCachedURLResponse (EMASCurl)

#pragma mark - Private Helper Methods

// 从响应头中解析Cache-Control指令
- (NSDictionary<NSString *, NSString *> *)emas_cacheControlDirectives {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return @{};
    }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
    NSString *cacheControlValue = httpResponse.allHeaderFields[EMASHTTPHeaderCacheControl];
    return EMASParseCacheControlDirectives(cacheControlValue);
}

// 计算响应的当前生命周期 (current_age)
// 使用存储的Date头和当前时间来计算。
- (NSTimeInterval)emas_currentAge {
    NSTimeInterval apparentAge = 0;
    NSTimeInterval residentTime = 0;

    // 响应的Date头
    NSString *dateHeaderString = self.userInfo[EMASUserInfoKeyOriginalDateHeader];
    NSDate *dateHeaderDate = EMASDateFromRFC1123String(dateHeaderString);

    NSTimeInterval responseTime = [self.userInfo[EMASUserInfoKeyStorageTimestamp] doubleValue]; // 响应被缓存的时间

    if (dateHeaderDate) {
        // apparent_age = max(0, response_time - date_value)
        apparentAge = MAX(0, responseTime - [dateHeaderDate timeIntervalSince1970]);
    }

    // resident_time = now - response_time
    residentTime = [[NSDate date] timeIntervalSince1970] - responseTime;

    // Age头的值 (如果有)
    NSTimeInterval ageHeaderValue = 0;
    if ([self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
        NSString *ageString = httpResponse.allHeaderFields[EMASHTTPHeaderAge];
        if (EMASCurlValidStr(ageString)) {
            ageHeaderValue = [ageString doubleValue];
        }
    }

    // corrected_age = apparent_age + resident_time
    // current_age = corrected_initial_age + resident_time (where corrected_initial_age = age_value + (response_time - date_value))
    // simplified: current_age = age_value + (now - date_value) - (if date_value is not present, use response_time as base)
    // More directly: current_age = age_value_at_receipt + (now - time_of_receipt)
    // age_value_at_receipt = MAX(age_header_value, apparent_age)
    return MAX(ageHeaderValue, apparentAge) + residentTime;
}

// 计算响应的保鲜期 (freshness_lifetime)
- (NSTimeInterval)emas_freshnessLifetime {
    NSDictionary<NSString *, NSString *> *directives = [self emas_cacheControlDirectives];

    // 优先使用 s-maxage (如果是共享缓存，但对于客户端私有缓存，max-age更相关)
    // NSString *sMaxAgeValue = directives[[EMASCacheControlSMaxAge lowercaseString]];
    // if (EMASCurlValidStr(sMaxAgeValue)) {
    //     return [sMaxAgeValue doubleValue];
    // }

    // 使用 max-age
    NSString *maxAgeValue = directives[[EMASCacheControlMaxAge lowercaseString]];
    if (EMASCurlValidStr(maxAgeValue)) {
        NSTimeInterval maxAge = [maxAgeValue doubleValue];
        return maxAge > 0 ? maxAge : 0; // max-age=0 表示立即过时
    }

    // 回退到 Expires 头
    NSString *expiresHeaderString = self.userInfo[EMASUserInfoKeyOriginalExpiresHeader];
    NSDate *expiresDate = EMASDateFromRFC1123String(expiresHeaderString);
    if (expiresDate) {
        NSString *dateHeaderString = self.userInfo[EMASUserInfoKeyOriginalDateHeader];
        NSDate *dateHeaderDate = EMASDateFromRFC1123String(dateHeaderString);
        if (dateHeaderDate) {
            // freshness_lifetime = expires_date - date_date
            NSTimeInterval lifetime = [expiresDate timeIntervalSinceDate:dateHeaderDate];
            return lifetime > 0 ? lifetime : 0;
        }
    }

    // 没有明确的保鲜信息，依赖启发式缓存 (NSURLCache可能会做，这里我们认为它不新鲜除非有明确指示)
    return 0;
}


#pragma mark - Public Methods

// 内部辅助方法，用于实际检查响应是否可缓存
+ (BOOL)isResponseCacheable:(NSHTTPURLResponse *)response {
    NSDictionary<NSString *, NSString *> *directives = EMASParseCacheControlDirectives(response.allHeaderFields[EMASHTTPHeaderCacheControl]);

    // 检查 Cache-Control: no-store
    if (directives[[EMASCacheControlNoStore lowercaseString]]) {
        return NO;
    }

    // 检查状态码
    // RFC 7231, Section 6.1: 200, 203, 204, 206 默认可缓存
    // 300, 301, (308) 如果有明确的Cache-Control或Expires也可缓存
    // 404, 405, 410, (501) 如果有明确的Cache-Control或Expires也可缓存
    switch (response.statusCode) {
        case 200: // OK
        case 203: // Non-Authoritative Information
        case 204: // No Content (注意：通常没有body，但headers可缓存)
        case 206: // Partial Content
            // 这些状态码默认可缓存，除非被Cache-Control覆盖
            break;
        case 300: // Multiple Choices
        case 301: // Moved Permanently
        // case 308: // Permanent Redirect (RFC 7538)
            // 这些需要显式的缓存头才能缓存
            if (!directives[[EMASCacheControlMaxAge lowercaseString]] && !response.allHeaderFields[EMASHTTPHeaderExpires]) {
                return NO;
            }
            break;
        case 404: // Not Found
        case 405: // Method Not Allowed
        case 410: // Gone
        // case 501: // Not Implemented (RFC 7231)
             // 这些负面响应也可以缓存，如果服务器指示
            if (!directives[[EMASCacheControlMaxAge lowercaseString]] && !response.allHeaderFields[EMASHTTPHeaderExpires] && !directives[[EMASCacheControlPublic lowercaseString]]) {
                return NO;
            }
            break;
        default:
            // 其他状态码默认不可缓存，除非显式允许 (例如，通过 Cache-Control: public)
            if (!directives[[EMASCacheControlPublic lowercaseString]]) {
                return NO;
            }
            break;
    }

    // 如果响应包含 Vary: *，则不能缓存 (RFC 7231 Section 7.1.4)
    NSString *varyHeader = response.allHeaderFields[EMASHTTPHeaderVary];
    if (varyHeader && [varyHeader isEqualToString:@"*"]) {
        return NO;
    }

    // 至少需要某种形式的验证器 (ETag/Last-Modified) 或明确的生命周期 (max-age/Expires) 才能有意义地缓存
    // Cache-Control: no-cache 本身也表示可以存储以备重新验证
    BOOL hasValidator = EMASCurlValidStr(response.allHeaderFields[EMASHTTPHeaderETag]) || EMASCurlValidStr(response.allHeaderFields[EMASHTTPHeaderLastModified]);
    BOOL hasExplicitLifetime = directives[[EMASCacheControlMaxAge lowercaseString]] || response.allHeaderFields[EMASHTTPHeaderExpires] != nil;
    BOOL isNoCacheDirectivePresent = directives[[EMASCacheControlNoCache lowercaseString]] != nil;

    if (!hasValidator && !hasExplicitLifetime && !isNoCacheDirectivePresent) {
        // 对于默认可缓存的状态码，如果没有任何缓存控制或验证器，NSURLCache可能会使用启发式缓存。
        // 为简化，这里我们要求至少有一个，或它是no-cache。
        // 对于200, 203, 204, 206，如果完全没有缓存头，理论上可以启发式缓存。
        // 但更安全的做法是要求明确指示或验证器。
        // 如果你希望支持启发式缓存，这里的逻辑需要调整。
        // 当前：如果不是no-cache，则需要验证器或生命周期信息。
        // return NO; // 根据策略，可以放宽此项，依赖NSURLCache的启发式。暂时注释掉以允许更多默认缓存。
    }

    return YES;
}

+ (nullable NSCachedURLResponse *)emas_cachedResponseWithHTTPURLResponse:(NSHTTPURLResponse *)response
                                                                    data:(NSData *)data
                                                              requestURL:(NSURL *)requestURL
                                                             httpVersion:(NSString *)httpVersion
                                                         originalRequest:(NSURLRequest *)originalRequest {
    if (![self isResponseCacheable:response]) {
        return nil;
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[EMASUserInfoKeyStorageTimestamp] = @([[NSDate date] timeIntervalSince1970]);

    NSString *dateHeader = response.allHeaderFields[EMASHTTPHeaderDate];
    if (EMASCurlValidStr(dateHeader)) {
        userInfo[EMASUserInfoKeyOriginalDateHeader] = dateHeader;
    }
    NSString *expiresHeader = response.allHeaderFields[EMASHTTPHeaderExpires];
    if (EMASCurlValidStr(expiresHeader)) {
        userInfo[EMASUserInfoKeyOriginalExpiresHeader] = expiresHeader;
    }
    if (EMASCurlValidStr(httpVersion)) {
        userInfo[EMASUserInfoKeyOriginalHTTPVersion] = httpVersion;
    }
    userInfo[EMASUserInfoKeyOriginalStatusCode] = @(response.statusCode);

    // 存储Vary头和对应的请求头值，用于后续缓存匹配验证
    NSString *varyHeader = response.allHeaderFields[EMASHTTPHeaderVary];
    if (EMASCurlValidStr(varyHeader) && ![varyHeader isEqualToString:@"*"]) {
        userInfo[EMASUserInfoKeyVaryHeader] = varyHeader;

        // 提取并存储Vary指定的请求头值
        NSMutableDictionary *varyValues = [NSMutableDictionary dictionary];
        NSArray *varyFields = [varyHeader componentsSeparatedByString:@","];
        for (NSString *field in varyFields) {
            NSString *trimmedField = [field stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmedField.length == 0) {
                continue;
            }
            NSString *value = [originalRequest valueForHTTPHeaderField:trimmedField];
            if (value) {
                varyValues[trimmedField.lowercaseString] = value;
            } else {
                varyValues[trimmedField.lowercaseString] = [NSNull null];
            }
        }
        userInfo[EMASUserInfoKeyVaryValues] = varyValues;
    }

    // NSURLCacheStorageAllowed意味着允许缓存，但最终是否缓存以及如何缓存仍由NSURLCache决定
    // (如果它有自己的更严格的规则)。
    return [[NSCachedURLResponse alloc] initWithResponse:response
                                                    data:data
                                                userInfo:userInfo
                                           storagePolicy:NSURLCacheStorageAllowed];
}


- (BOOL)emas_isResponseStillFreshForRequest:(nullable NSURLRequest *)request {
    // 检查请求中是否有强制不使用缓存的指令
    if (request) {
        NSString *requestCacheControl = [request valueForHTTPHeaderField:EMASHTTPHeaderCacheControl];
        NSDictionary<NSString *, NSString *> *reqDirectives = EMASParseCacheControlDirectives(requestCacheControl);
        if (reqDirectives[EMASCacheControlNoCache]) { // 请求要求不使用缓存，直接联系服务器
            return NO;
        }
        NSString *pragma = [request valueForHTTPHeaderField:EMASHTTPHeaderPragma];
        if ([pragma isEqualToString:EMASCacheControlNoCache]) { // HTTP/1.0
            return NO;
        }
        // max-age=0 in request also means revalidate
        if (reqDirectives[EMASCacheControlMaxAge]) {
            if ([reqDirectives[EMASCacheControlMaxAge] isEqualToString:@"0"]) {
                return NO; // 必须重新验证
            }
        }
    }

    NSDictionary<NSString *, NSString *> *directives = [self emas_cacheControlDirectives];

    // 如果响应中有 no-cache，则它从不是新鲜的，总需要验证
    if (directives[[EMASCacheControlNoCache lowercaseString]]) {
        return NO;
    }

    // 如果响应中有 must-revalidate，并且已过期，则不是新鲜的
    // (这个检查实际发生在 currentAge >= freshnessLifetime 之后)

    NSTimeInterval freshnessLifetime = [self emas_freshnessLifetime];
    NSTimeInterval currentAge = [self emas_currentAge];

    BOOL isFresh = currentAge < freshnessLifetime;

    if (!isFresh && directives[[EMASCacheControlMustRevalidate lowercaseString]]) {
        // 如果过期了并且有must-revalidate，则绝对不能用陈旧的。
        return NO;
    }

    return isFresh;
}

- (BOOL)emas_requiresRevalidation {
    NSDictionary<NSString *, NSString *> *directives = [self emas_cacheControlDirectives];
    if (directives[[EMASCacheControlNoCache lowercaseString]]) {
        return YES; // no-cache 要求每次都重新验证
    }
    // 如果已过期且存在 must-revalidate，也要求重新验证 (此方法本身不检查是否过期)
    // 简单来说，no-cache是主要的“必须重新验证”信号，除非它新鲜。
    return NO;
}

- (BOOL)emas_mustRevalidate {
    NSDictionary<NSString *, NSString *> *directives = [self emas_cacheControlDirectives];
    return directives[[EMASCacheControlMustRevalidate lowercaseString]] != nil;
}


- (nullable NSString *)emas_etag {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return nil;
    }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
    return httpResponse.allHeaderFields[EMASHTTPHeaderETag];
}

- (nullable NSString *)emas_lastModified {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return nil;
    }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self.response;
    return httpResponse.allHeaderFields[EMASHTTPHeaderLastModified];
}

- (NSCachedURLResponse *)emas_updatedResponseWithHeadersFrom304Response:(NSDictionary *)newHeaders {
    if (![self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return self; // 无法处理
    }
    NSHTTPURLResponse *originalResponse = (NSHTTPURLResponse *)self.response;
    NSMutableDictionary *updatedHeaders = [originalResponse.allHeaderFields mutableCopy];

    // 根据RFC 7232 Section 4.1, 304响应应包含这些头，如果它们在200 OK中会出现
    // Cache MUST update these if present in the 304 response.
    NSArray<NSString *> *headersToUpdateFrom304 = @[
        EMASHTTPHeaderCacheControl, EMASHTTPHeaderDate, EMASHTTPHeaderETag,
        EMASHTTPHeaderExpires, EMASHTTPHeaderLastModified, EMASHTTPHeaderVary,
        @"Content-Location" // 另一个例子
    ];

    for (NSString *key in headersToUpdateFrom304) {
        if (newHeaders[key]) {
            updatedHeaders[key] = newHeaders[key];
        }
    }

    // HTTP 版本和状态码应来自原始缓存的响应
    NSString *httpVersion = self.userInfo[EMASUserInfoKeyOriginalHTTPVersion] ?: @"HTTP/1.1";
    NSInteger statusCode = [self.userInfo[EMASUserInfoKeyOriginalStatusCode] integerValue] ?: originalResponse.statusCode;
    if (statusCode == 0 && originalResponse.statusCode != 304) statusCode = originalResponse.statusCode; // 确保有有效的原始状态码
    else if (statusCode == 0) statusCode = 200; // 如果都找不到，默认200


    NSHTTPURLResponse *newSynthesizedResponse = [[NSHTTPURLResponse alloc] initWithURL:originalResponse.URL
                                                                          statusCode:statusCode
                                                                         HTTPVersion:httpVersion
                                                                        headerFields:[updatedHeaders copy]];

    // 更新userInfo中的时间戳和可能的Date/Expires头
    NSMutableDictionary *updatedUserInfo = [self.userInfo mutableCopy];
    updatedUserInfo[EMASUserInfoKeyStorageTimestamp] = @([[NSDate date] timeIntervalSince1970]);
    if (newHeaders[EMASHTTPHeaderDate]) {
        updatedUserInfo[EMASUserInfoKeyOriginalDateHeader] = newHeaders[EMASHTTPHeaderDate];
    }
    if (newHeaders[EMASHTTPHeaderExpires]) {
        updatedUserInfo[EMASUserInfoKeyOriginalExpiresHeader] = newHeaders[EMASHTTPHeaderExpires];
    }

    return [[NSCachedURLResponse alloc] initWithResponse:newSynthesizedResponse
                                                    data:self.data // 304响应不包含数据，重用旧数据
                                                userInfo:updatedUserInfo
                                           storagePolicy:self.storagePolicy]; // 重用旧存储策略
}

- (BOOL)emas_matchesVaryHeadersForRequest:(NSURLRequest *)request {
    NSString *varyHeader = self.userInfo[EMASUserInfoKeyVaryHeader];
    if (!varyHeader) {
        return YES;
    }

    NSDictionary *storedVaryValues = self.userInfo[EMASUserInfoKeyVaryValues];
    if (!storedVaryValues) {
        return YES;
    }

    NSArray *varyFields = [varyHeader componentsSeparatedByString:@","];
    for (NSString *field in varyFields) {
        NSString *trimmedField = [field stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmedField.length == 0) {
            continue;
        }

        id storedValue = storedVaryValues[trimmedField.lowercaseString];
        NSString *requestValue = [request valueForHTTPHeaderField:trimmedField];

        // 比较值（考虑NSNull表示原始请求中该头不存在的情况）
        if ([storedValue isKindOfClass:[NSNull class]]) {
            if (requestValue != nil) {
                return NO;
            }
        } else if ([storedValue isKindOfClass:[NSString class]]) {
            if (requestValue == nil) {
                return NO;
            }
            if (![storedValue isEqualToString:requestValue]) {
                return NO;
            }
        }
    }
    return YES;
}

# pragma mark - Helper Functions

/**
 * 检查字符串是否有效 (非nil, NSString类型, 长度大于0)
 */
BOOL EMASCurlValidStr(NSString * _Nullable str) {
    return (str != nil && [str isKindOfClass:[NSString class]] && str.length > 0);
}

/**
 * 将RFC1123日期字符串 (以及兼容的旧格式) 转换为NSDate对象。
 * HTTP日期应始终为GMT。
 */
NSDate * _Nullable EMASDateFromRFC1123String(NSString * _Nullable rfc1123String) {
    if (!EMASCurlValidStr(rfc1123String)) {
        return nil;
    }

    static NSDateFormatter *rfc1123DateFormatter = nil;
    static NSDateFormatter *rfc850DateFormatter = nil;
    static NSDateFormatter *asctimeDateFormatter = nil;

    // 缓存 NSDateFormatter 实例以提高性能，因为创建它们相对昂贵。
    // 注意：NSDateFormatter 不是线程安全的，所以如果在多线程环境中使用，需要特别处理。
    // 如果这些函数只在特定队列（例如 s_cacheQueue）上调用，则这种缓存方式是安全的。
    // 如果可能从不同线程调用，则需要为每个线程创建或使用 @synchronized。
    // 这里假设它在受控环境中使用。
    // 初始化格式化器
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLocale *posixLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        NSTimeZone *gmtTimeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

        // RFC 1123 format (首选格式)
        rfc1123DateFormatter = [[NSDateFormatter alloc] init];
        [rfc1123DateFormatter setLocale:posixLocale];
        [rfc1123DateFormatter setTimeZone:gmtTimeZone];
        // 格式: Sun, 06 Nov 1994 08:49:37 GMT
        [rfc1123DateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss zzz"];

        // RFC 850 format (过时)
        rfc850DateFormatter = [[NSDateFormatter alloc] init];
        [rfc850DateFormatter setLocale:posixLocale];
        [rfc850DateFormatter setTimeZone:gmtTimeZone];
        // 格式: Sunday, 06-Nov-94 08:49:37 GMT
        [rfc850DateFormatter setDateFormat:@"EEEE, dd-MMM-yy HH:mm:ss zzz"];

        // ANSI C's asctime() format (过时)
        asctimeDateFormatter = [[NSDateFormatter alloc] init];
        [asctimeDateFormatter setLocale:posixLocale];
        [asctimeDateFormatter setTimeZone:gmtTimeZone];
        // 格式: Sun Nov  6 08:49:37 1994
        [asctimeDateFormatter setDateFormat:@"EEE MMM d HH:mm:ss yyyy"];
    });

    NSDate *date = nil;

    // 尝试按首选顺序解析
    date = [rfc1123DateFormatter dateFromString:rfc1123String];
    if (date != nil) {
        return date;
    }

    date = [rfc850DateFormatter dateFromString:rfc1123String];
    if (date != nil) {
        return date;
    }

    date = [asctimeDateFormatter dateFromString:rfc1123String];
    if (date != nil) {
        return date;
    }

    // 如果所有已知格式都失败，则返回nil
    return nil;
}

/**
 * 解析Cache-Control头的值为一个字典。
 * 键是指令名(小写)，值是指令值(如果存在，否则为空字符串)。
 * 处理逗号分隔的指令列表。
 */
NSDictionary<NSString *, NSString *> * _Nonnull EMASParseCacheControlDirectives(NSString * _Nullable cacheControlValue) {
    if (!EMASCurlValidStr(cacheControlValue)) {
        return @{}; // 返回空字典，如果输入无效
    }

    NSMutableDictionary<NSString *, NSString *> *directives = [NSMutableDictionary dictionary];
    // 按逗号分割指令
    NSArray<NSString *> *components = [cacheControlValue componentsSeparatedByString:@","];

    for (NSString *component in components) {
        // 去除指令两端的空白字符
        NSString *trimmedComponent = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmedComponent.length == 0) {
            continue; // 跳过空部分
        }

        // 检查指令是否包含 '='
        NSRange equalsRange = [trimmedComponent rangeOfString:@"="];
        NSString *directiveName;
        NSString *directiveValue = @""; // 默认值为空字符串，表示指令存在但没有值

        if (equalsRange.location == NSNotFound) {
            // 没有'='，整个组件是指令名称
            directiveName = trimmedComponent;
        } else {
            // 有'='，分割名称和值
            directiveName = [[trimmedComponent substringToIndex:equalsRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            directiveValue = [[trimmedComponent substringFromIndex:equalsRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

            // 去除值两端的引号 (如果存在)
            if ([directiveValue hasPrefix:@"\""] && [directiveValue hasSuffix:@"\""] && directiveValue.length > 1) {
                directiveValue = [directiveValue substringWithRange:NSMakeRange(1, directiveValue.length - 2)];
            }
        }

        if (directiveName.length > 0) {
            // 将指令名称转换为小写以进行不区分大小写的比较
            NSString *lowercaseName = [directiveName lowercaseString];
            directives[lowercaseName] = directiveValue;
        }
    }

    return [directives copy]; // 返回不可变副本
}

@end
