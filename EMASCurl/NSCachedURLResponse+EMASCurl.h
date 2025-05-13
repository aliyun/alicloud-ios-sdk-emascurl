//
//  NSCachedURLResponse+EMASCurl.h
//  EMASCurl
//
//  Created by xuyecan on 2025/5/12.
//

#import <Foundation/Foundation.h>
#import "EMASCurlCacheConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSCachedURLResponse (EMASCurl)

/**
 * 检查此缓存的响应是否仍然可用 (基于HTTP规范检查Cache-Control, Expires等)
 * @param request 可选的原始请求，用于检查请求特定的缓存指令 (例如，请求中的Cache-Control: max-age=0)
 * 当前实现主要关注响应的生命周期。
 */
- (BOOL)emas_isResponseStillFreshForRequest:(nullable NSURLRequest *)request;

/**
 * 获取ETag值，用于条件请求 (If-None-Match)
 */
- (nullable NSString *)emas_etag;

/**
 * 获取Last-Modified值，用于条件请求 (If-Modified-Since)
 */
- (nullable NSString *)emas_lastModified;

/**
 * 使用来自304 Not Modified响应的新HTTP头更新此缓存响应的元数据。
 * @param newHeaders 来自304响应的头字段。
 * @return 一个新的NSCachedURLResponse实例，其中包含更新后的头和原始数据。
 */
- (NSCachedURLResponse *)emas_updatedResponseWithHeadersFrom304Response:(NSDictionary *)newHeaders;

/**
 * 根据HTTP响应创建一个NSCachedURLResponse实例。
 * 此方法会检查响应是否根据HTTP规范可以被缓存。
 * 如果响应不可缓存 (例如，包含Cache-Control: no-store)，则返回nil。
 *
 * @param response HTTP响应对象
 * @param data 响应体数据
 * @param requestURL 原始请求的URL (用于NSCachedURLResponse初始化)
 * @param httpVersion 原始响应的HTTP版本 (例如 "HTTP/1.1")
 * @return 一个新的NSCachedURLResponse实例，如果可缓存；否则为nil。
 */
+ (nullable NSCachedURLResponse *)emas_cachedResponseWithHTTPURLResponse:(NSHTTPURLResponse *)response
                                                                    data:(NSData *)data
                                                              requestURL:(NSURL *)requestURL
                                                             httpVersion:(NSString *)httpVersion;

/**
 * 指示此特定缓存条目是否包含Cache-Control: must-revalidate指令。
 */
- (BOOL)emas_mustRevalidate;

/**
 * 指示此特定缓存条目是否包含Cache-Control: no-cache指令。
 * no-cache意味着它可以被存储，但每次使用前必须与服务器重新验证。
 */
- (BOOL)emas_requiresRevalidation;


@end

NS_ASSUME_NONNULL_END
