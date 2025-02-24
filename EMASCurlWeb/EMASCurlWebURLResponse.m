//
//  EMASCurlCachedURLResponse.m

#import "EMASCurlWebURLResponse.h"
#import "EMASCurlWebUtils.h"

@interface EMASCurlWebURLResponse ()
@property (readwrite, copy) NSHTTPURLResponse *response;
@property (readwrite, copy) NSData *data;
@property (readwrite, assign) unsigned long long timestamp;
@property (readwrite, assign) unsigned long long maxAge;
@property (readwrite, copy) NSString *etag;
@property (readwrite, copy) NSString *lastModified;
@end

@implementation EMASCurlWebURLResponse {
    BOOL _canSave;
}

#pragma mark - Initialization

// 初始化实例，并解析响应头信息
- (instancetype)initWithResponse:(NSHTTPURLResponse *)response data:(NSData *)data {
    self = [super init];
    if (self) {
        _response = response;
        _data = data;
        _timestamp = (unsigned long long)[NSDate new].timeIntervalSince1970;
        [self parseResponseHeader];
    }
    return self;
}

#pragma mark - Public Methods

// 返回是否允许缓存
- (BOOL)canCache {
    return _canSave;
}

// 检查缓存是否过期
- (BOOL)isExpired {
    unsigned long long now = (unsigned long long)[NSDate new].timeIntervalSince1970;
    return (now - self.timestamp) >= self.maxAge;
}

// 更新响应头字段，并刷新缓存属性
- (void)updateWithResponse:(NSDictionary *)newHeaderFields {
    [self mergeHeaderFields:newHeaderFields];
    self.timestamp = (unsigned long long)[NSDate new].timeIntervalSince1970;
    [self updateCacheProperties];
}

#pragma mark - Helper Methods

// 合并旧的和新的header fields，生成更新后的响应
- (void)mergeHeaderFields:(NSDictionary *)newHeaderFields {
    NSMutableDictionary *headerFields = [self.response.allHeaderFields mutableCopy];
    [newHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        if (!EMASCurlValidStr(key) || !EMASCurlValidStr(value)) {
            return;
        }
        NSString *oldValue = self.response.allHeaderFields[key];
        if (!EMASCurlValidStr(oldValue)) {
            return;
        }
        headerFields[key] = value;
    }];
    NSHTTPURLResponse *updatedResponse = [[NSHTTPURLResponse alloc] initWithURL:self.response.URL
                                                                     statusCode:self.response.statusCode
                                                                    HTTPVersion:@"HTTP/2"
                                                                   headerFields:[headerFields copy]];
    self.response = updatedResponse;
}

// 更新缓存相关的属性，如maxAge、etag、lastModified
- (void)updateCacheProperties {
    [self parseCacheControl];
    if (!_canSave) {
        return;
    }
    [self parseEtag];
    if (!EMASCurlValidStr(self.etag)) {
        [self parseLastModified];
    }
}

// 检查响应是否满足缓存要求：状态码、Content-Type等
- (BOOL)isResponseValidForCaching {
    if (self.response.statusCode != 200) {
        return NO;
    }
    NSString *contentType = self.response.allHeaderFields[@"Content-Type"];
    if (!EMASCurlValidStr(contentType)) {
        return NO;
    }
    if ([contentType containsString:@"text/html"] || [contentType containsString:@"video"]) {
        return NO;
    }
    return YES;
}

// 解析响应头，先检查是否满足缓存条件，再更新缓存属性
- (void)parseResponseHeader {
    if (![self isResponseValidForCaching]) {
        _canSave = NO;
        return;
    }
    [self updateCacheProperties];
}

 // 解析Cache-Control字段，并设置缓存有效期
- (void)parseCacheControl {
    NSString *cacheControl = self.response.allHeaderFields[@"Cache-Control"];
    if (!EMASCurlValidStr(cacheControl)) {
        _canSave = NO;
        return;
    }

    NSArray<NSString *> *controlItems = [cacheControl componentsSeparatedByString:@","];
    BOOL shouldCache = NO;
    unsigned long long maxAgeValue = 0;

    for (NSString *item in controlItems) {
        NSString *trimmedItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmedItem isEqualToString:@"no-cache"] || [trimmedItem isEqualToString:@"no-store"]) {
            shouldCache = NO;
            break;
        }
        if ([trimmedItem hasPrefix:@"max-age"] && trimmedItem.length > 8) {
            long long age = [[trimmedItem substringFromIndex:8] longLongValue];
            if (age > 0) {
                maxAgeValue = age;
                shouldCache = YES;
            }
        }
    }

    _canSave = shouldCache;
    self.maxAge = maxAgeValue;
}

 // 解析Etag字段
- (void)parseEtag {
    NSString *etagValue = self.response.allHeaderFields[@"Etag"];
    if (EMASCurlValidStr(etagValue)) {
        self.etag = etagValue;
    }
}

 // 解析Last-Modified字段
- (void)parseLastModified {
    NSString *lastModifiedValue = self.response.allHeaderFields[@"Last-Modified"];
    if (EMASCurlValidStr(lastModifiedValue)) {
        self.lastModified = lastModifiedValue;
    }
}

#pragma mark - NSCopying

// 创建当前实例的拷贝
- (id)copyWithZone:(nullable NSZone *)zone {
    EMASCurlWebURLResponse *cacheResponse = [[[self class] allocWithZone:zone] initWithResponse:self.response
                                                                                              data:self.data];
    cacheResponse.timestamp = self.timestamp;
    cacheResponse.maxAge = self.maxAge;
    cacheResponse.etag = self.etag;
    cacheResponse.lastModified = self.lastModified;
    return cacheResponse;
}

#pragma mark - NSCoding

// 对象编码，保存必要属性
- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeObject:self.response forKey:@"response"];
    [coder encodeObject:self.data forKey:@"data"];
    [coder encodeDouble:self.timestamp forKey:@"timestamp"];
    [coder encodeInt64:self.maxAge forKey:@"maxAge"];
    [coder encodeObject:self.etag forKey:@"etag"];
    [coder encodeObject:self.lastModified forKey:@"lastModified"];
}

// 对象解码，恢复保存的属性
- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        self.response = [coder decodeObjectForKey:@"response"];
        self.data = [coder decodeObjectForKey:@"data"];
        self.timestamp = [coder decodeDoubleForKey:@"timestamp"];
        self.maxAge = [coder decodeInt64ForKey:@"maxAge"];
        self.etag = [coder decodeObjectForKey:@"etag"];
        self.lastModified = [coder decodeObjectForKey:@"lastModified"];
    }
    return self;
}

@end
