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
 * 缓存HTTP响应
 *
 * @param response HTTP响应
 * @param data 响应数据
 * @param request 原始请求
 */
- (void)cacheWithHTTPURLResponse:(NSHTTPURLResponse *)response
                            data:(NSData *)data
                         request:(NSURLRequest *)request;

/**
 * 获取请求对应的缓存响应
 *
 * @param request 请求
 * @return 缓存的响应，如果没有缓存或缓存已失效且无条件验证标记则返回nil
 */
- (nullable NSCachedURLResponse *)getCachedResponseWithRequest:(NSURLRequest *)request;

/**
 * 使用新的HTTP响应头更新缓存的响应
 * 通常用于处理304 Not Modified响应
 *
 * @param newResponse 新的HTTP响应
 * @param request 原始请求
 * @return 更新后的缓存响应，如果更新失败则返回nil
 */
- (nullable NSCachedURLResponse *)updateCachedResponseWithURLResponse:(NSHTTPURLResponse *)newResponse
                                                              request:(NSURLRequest *)request;

@end

NS_ASSUME_NONNULL_END
