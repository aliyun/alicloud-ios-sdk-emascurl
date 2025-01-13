//
//  WKWebViewConfiguration+Loader.h

#import <WebKit/WebKit.h>
#import "EMASCurlCacheLoader.h"


NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(LimitVersion))
@interface WKWebViewConfiguration (Loader)

@property (nonatomic, strong, readonly, nullable) EMASCurlCacheLoader *loader;

@end

NS_ASSUME_NONNULL_END
