//
//  EMASCurlCookieStorage.h
//  EMASCurl
//
//  Created by xuyecan on 2025/2/3.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlCookieStorage : NSObject

+ (instancetype)sharedStorage;

/**
 * 从 Set-Cookie header 值设置 cookies
 */
- (void)setCookieWithString:(NSString *)cookieString forURL:(NSURL *)url;

/**
 * 获取指定 URL 的 cookie 字符串
 */
- (NSString *)cookieStringForURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
