//
//  WKWebViewConfiguration+Loader.h

#import <WebKit/WebKit.h>
#import "EMASCurlWebConstant.h"

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(LimitVersion))
@protocol EMASCurlWebViewRedirectDelegate <NSObject>

- (void)redirectWithRequest:(NSURLRequest *)redirectRequest;

@end

API_AVAILABLE(ios(LimitVersion))
@interface WKWebViewConfiguration (Loader) <EMASCurlWebViewRedirectDelegate>

@property(nonatomic, weak) WKWebView *wkWebView;

- (void)enableCookieHandler;

@end

NS_ASSUME_NONNULL_END
