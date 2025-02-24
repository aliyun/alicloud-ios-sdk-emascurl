//
//  EMASCurlWkWebViewContentLoader.h
//  EMASCurl
//
//  Created by xuyecan on 2025/2/4.
//

#import <Foundation/Foundation.h>
#import "EMASCurlWebConstant.h"

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(LimitVersion))
@interface EMASCurlWebContentLoader : NSObject

+ (void)initializeInterception;

+ (void)setDebugLogEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
