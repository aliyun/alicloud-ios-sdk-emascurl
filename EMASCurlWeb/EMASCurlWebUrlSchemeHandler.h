//
//  EMASCurlUrlSchemeHandler.h
//  EMASCurl
//
//  Created by xuyecan on 2025/2/3.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import "WKWebViewConfiguration+Loader.h"

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(LimitVersion))
@interface EMASCurlWebUrlSchemeHandler : NSObject<WKURLSchemeHandler>

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
