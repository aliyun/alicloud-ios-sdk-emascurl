//
//  EMASCurlWebLogger.h
//  EMASCurl
//
//  Created by xuyecan on 2025/2/5.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void EMASCurlCacheLog(NSString * _Nonnull format, ...) ;

@interface EMASCurlWebLogger : NSObject

+ (void)setDebugLogEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
