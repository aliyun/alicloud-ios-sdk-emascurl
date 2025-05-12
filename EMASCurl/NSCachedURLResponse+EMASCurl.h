//
//  NSCachedURLResponse+EMASCurl.h
//  EMASCurl
//
//  Created by xuyecan on 2025/5/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSCachedURLResponse (EMASCurl)

/**
 * 检查响应是否可以缓存
 * 基于HTTP规范检查状态码和缓存控制头
 */
- (BOOL)emas_canCache;

/**
 * 检查缓存是否已过期
 * 基于Cache-Control中的max-age和存储的时间戳
 */
- (BOOL)emas_isExpired;

/**
 * 获取ETag值，用于条件请求
 */
- (nullable NSString *)emas_etag;

/**
 * 获取Last-Modified值，用于条件请求
 */
- (nullable NSString *)emas_lastModified;

/**
 * 使用新的HTTP头更新缓存响应
 * 用于304 Not Modified响应场景
 */
- (NSCachedURLResponse *)emas_updatedResponseWithHeaderFields:(NSDictionary *)newHeaderFields;

/**
 * 创建缓存响应
 * 会检查响应是否可缓存，如不可缓存返回nil
 */
+ (nullable NSCachedURLResponse *)emas_cachedResponseWithResponse:(NSHTTPURLResponse *)response
                                                            data:(NSData *)data
                                                             url:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
