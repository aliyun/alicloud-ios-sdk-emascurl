//
//  WKWebViewConfiguration+Loader.m

#import "WKWebViewConfiguration+Loader.h"
#import "EMASCurlWebUrlSchemeHandler.h"
#import <objc/runtime.h>
#import "EMASCurlWebUtils.h"
#import "EMASCurlWebLogger.h"


static void *kEMASCurlStoreWebViewWeakReferenceKey = &kEMASCurlStoreWebViewWeakReferenceKey;


@interface EMASCurlWebMessageHandler: NSObject<WKScriptMessageHandler>

@end


@implementation EMASCurlWebMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"EMASCurlWebMessageHandler"]) {
        NSDictionary *body = message.body;
        NSString *method = body[@"method"];

        if ([method isEqualToString:@"syncCookie"]) {
            NSDictionary *params = body[@"params"];
            NSString *cookieStr = params[@"cookie"];
            NSString *urlStr = params[@"url"];
            [self saveCookieFromString:cookieStr forURL:urlStr];
        }
    }
}

- (void)saveCookieFromString:(NSString *)cookieStr forURL:(NSString *)urlStr {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url || cookieStr.length == 0) return;

    // 解析 "Set-Cookie" 并存到 NSHTTPCookieStorage
    // （如果需要更细粒度控制，可自行手动解析）
    NSDictionary *cookieHeaders = @{@"Set-Cookie" : cookieStr};
    NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:cookieHeaders
                                                                             forURL:url];
    for (NSHTTPCookie *cookie in cookies) {
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
    }
}

@end


@interface WKWebViewConfiguration () <WKScriptMessageHandler>

@end


@implementation WKWebViewConfiguration (Loader)

- (void)setWkWebView:(WKWebView *)wkWebView {
    objc_setAssociatedObject(self, kEMASCurlStoreWebViewWeakReferenceKey, wkWebView, OBJC_ASSOCIATION_ASSIGN);
}

- (WKWebView *)wkWebView {
    return objc_getAssociatedObject(self, kEMASCurlStoreWebViewWeakReferenceKey);
}

- (void)redirectWithRequest:(NSURLRequest *)redirectRequest {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.wkWebView loadRequest:redirectRequest];
    });
}

- (void)enableCookieHandler {
    NSString *bundlePath = [[NSBundle bundleForClass:NSClassFromString(@"EMASCurlWebContentLoader")] pathForResource:@"EMASCurlWebBundle" ofType:@"bundle"];
    NSBundle *resourceBundle = [NSBundle bundleWithPath:bundlePath];
    NSString *filePath = [resourceBundle pathForResource:@"cookie" ofType:@"js"];
    NSString *scriptContent = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    if (EMASCurlValidStr(scriptContent)) {
        WKUserContentController *userContentController = [[WKUserContentController alloc] init];
        WKUserScript *userScript = [[WKUserScript alloc] initWithSource:scriptContent injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
        [userContentController addUserScript:userScript];
        [userContentController addScriptMessageHandler:[EMASCurlWebMessageHandler new] name:@"EMASCurlWebMessageHandler"];
        self.userContentController = userContentController;
    }
}

@end
