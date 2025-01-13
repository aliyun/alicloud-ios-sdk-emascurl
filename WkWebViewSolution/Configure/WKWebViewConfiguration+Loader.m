//
//  WKWebViewConfiguration+Loader.m

#import "WKWebViewConfiguration+Loader.h"
#import <objc/runtime.h>
#import "EMASCurlUtils.h"

@interface EMASCurlCacheLoader (Private)

@property (nonatomic, weak) WKWebViewConfiguration * configuration;

@end

static void *EMASCurlCacheLoaderKey = &EMASCurlCacheLoaderKey;

@implementation WKWebViewConfiguration (Loader)

- (nullable EMASCurlCacheLoader *)loader API_AVAILABLE(ios(LimitVersion)){
    if (@available(iOS LimitVersion, *)) {
        EMASCurlCacheLoader* loader = objc_getAssociatedObject(self, EMASCurlCacheLoaderKey);
        if (!loader) {
            loader = [EMASCurlCacheLoader new];
            loader.configuration = self;
            objc_setAssociatedObject(self, EMASCurlCacheLoaderKey, loader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return loader;
        }
        return loader;
    } else {
        return nil;
    }
}

@end
