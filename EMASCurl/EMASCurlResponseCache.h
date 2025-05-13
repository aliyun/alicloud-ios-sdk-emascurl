//
//  EMASCurlResponseCache.h
//  EMASCurl
//
//  Created by xuyecan on 2025/5/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlResponseCache : NSObject

/**
 * 缓存HTTP响应。
 * 此方法会先通过 NSCachedURLResponse+EMASCurl 中的方法检查响应是否适合缓存。
 *
 * @param response HTTP响应
 * @param data 响应数据
 * @param request 原始请求 (用于存储到NSURLCache)
 * @param httpVersion 原始响应的HTTP版本 (例如 "HTTP/1.1", "HTTP/2")
 */
- (void)cacheResponse:(NSHTTPURLResponse *)response
                 data:(NSData *)data
           forRequest:(NSURLRequest *)request
      withHTTPVersion:(NSString *)httpVersion; // 添加 httpVersion 参数

/**
 * 获取请求对应的缓存响应。
 * 此方法会返回一个缓存响应，如果它存在且:
 * 1. 仍然新鲜 (fresh)
 * 2. 或已过期 (stale) 但包含验证器 (ETag/Last-Modified)，可用于条件GET。
 * 如果缓存响应已过期且没有验证器，它将被从缓存中移除并返回nil。
 *
 * @param request 请求
 * @return 缓存的响应，或nil。
 */
- (nullable NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request;

/**
 * 当收到304 Not Modified响应时，使用新的HTTP响应头更新缓存的响应。
 *
 * @param newResponseHeaders 来自304响应的头字段
 * @param request 触发304的原始请求
 * @return 更新后的缓存响应，如果更新成功；否则返回nil。
 */
- (nullable NSCachedURLResponse *)updateCachedResponseWithHeaders:(NSDictionary *)newResponseHeaders
                                                       forRequest:(NSURLRequest *)request;

@end

NS_ASSUME_NONNULL_END
