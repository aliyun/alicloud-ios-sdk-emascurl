//
//  EMASCurlCacheLoader.m

#import "EMASCurlCacheLoader.h"
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import "EMASCurlWeakProxy.h"
#import "EMASCurlResourceMatcherManager.h"

#import "WKWebViewConfiguration+Loader.h"

API_AVAILABLE(ios(LimitVersion))

static void *EMASCurlCacheConfigurationKey = &EMASCurlCacheConfigurationKey;

@implementation WKProcessPool (EMASCurlCache)

+ (instancetype)sharePool {
    static WKProcessPool *pool = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        pool = [[WKProcessPool alloc] init];
    });
    return pool;
}

@end

@interface EMASCurlCacheLoader ()<EMASCurlResourceMatcherManagerDelegate>

@property (nonatomic, copy) NSArray *schemes;

@property (nonatomic, weak) WKWebView *webView;

@property (nonatomic, weak) WKWebViewConfiguration * configuration;

@property (nonatomic, strong) EMASCurlWeakProxy * proxy;

@property (nonatomic, strong) EMASCurlResourceMatcherManager *resMatcherManager;

@end

@implementation EMASCurlCacheLoader{
    BOOL _addHookJs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _schemes = @[@"https", @"http"];
        _resMatcherManager = [EMASCurlResourceMatcherManager new];
        _resMatcherManager.delegate = self;
    }
    return self;
}

- (void)setEnable:(BOOL)enable {
    if (@available(iOS LimitVersion, *)) {
        if (enable && !_enable) {
            [EMASCurlCacheLoader hook];
            [EMASCurlCacheLoader handleBlobData];
            
            [self sharePool];
            // [self addHookJs];
            // [self registerJSBridge];
            [self registerSchemes];
        }
        _enable = enable;
    }
}

- (void)setWebView:(WKWebView *)webView{
    _webView = webView;
    objc_setAssociatedObject(_webView, EMASCurlCacheConfigurationKey, self.configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)sharePool {
    self.configuration.processPool = [WKProcessPool sharePool];
}

- (void)addHookJs{
    if (_addHookJs) {
        return;
    }
    _addHookJs = YES;
    {
        NSString *path = [[NSBundle bundleForClass:NSClassFromString(@"EMASCurlCache")] pathForResource:@"EMASCurlCache" ofType:@"bundle"];
        NSString *js = [NSString stringWithContentsOfFile:[path stringByAppendingPathComponent:@"hook.js"] encoding:NSUTF8StringEncoding error:nil];
        if (EMASCurlValidStr(js)) {
            [self.configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        }
    }
    {
        NSString *path = [[NSBundle bundleForClass:NSClassFromString(@"EMASCurlCache")] pathForResource:@"EMASCurlCache" ofType:@"bundle"];
        NSString *js = [NSString stringWithContentsOfFile:[path stringByAppendingPathComponent:@"cookie.js"] encoding:NSUTF8StringEncoding error:nil];
        if (EMASCurlValidStr(js)) {
            [self.configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        }
    }
    
}

- (void)registerSchemes {
    if (@available(iOS LimitVersion, *)) {
        [self.schemes enumerateObjectsUsingBlock:^(NSString * _Nonnull scheme, NSUInteger idx, BOOL * _Nonnull stop) {
            if (!EMASCurlValidStr(scheme)) {
                return;
            }
            if (![WKWebView handlesURLScheme:scheme] && ![self.configuration urlSchemeHandlerForURLScheme:scheme]){
                [self.configuration setURLSchemeHandler:self.proxy forURLScheme:scheme];
            }
        }];
    }
}

#pragma mark - hook
+ (void)hook{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [WKWebView class];
        {
            __block BOOL (*oldImp)(id,SEL,id)  = NULL;
            SEL sel = @selector(handlesURLScheme:);
            IMP newImp = imp_implementationWithBlock(^(id obj, NSString* scheme){
                return NO;
            });
            Method method = class_getInstanceMethod(object_getClass(cls), sel);
            oldImp = (BOOL (*)(id,SEL,id))method_getImplementation(method);
            if (!class_addMethod(object_getClass(cls), sel, newImp, method_getTypeEncoding(method))) {
                oldImp = (BOOL (*)(id,SEL,id))method_setImplementation(method, newImp);
            }
        }
        {
            __block WKWebView* (*oldImp)(id,SEL,CGRect,id)  = NULL;
            SEL sel = @selector(initWithFrame:configuration:);
            IMP newImp = imp_implementationWithBlock(^(id obj, CGRect frame, WKWebViewConfiguration*configuration){
                WKWebView *webview = oldImp(obj,sel,frame,configuration);
                if (configuration.loader.enable) {
                    configuration.loader.webView = webview;
                }
                return webview;
            });
            Method method = class_getInstanceMethod(cls, sel);
            oldImp = (WKWebView* (*)(id,SEL,CGRect,id))method_getImplementation(method);
            if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(method))) {
                oldImp = (WKWebView* (*)(id,SEL,CGRect,id))method_setImplementation(method, newImp);
            }
        }
    });
}
                  
+ (void)handleBlobData {
  BOOL canHandleBlob = NO;
  if(@available(iOS LimitVersion, *)){
      canHandleBlob = YES;
  }
  if (!canHandleBlob) {
      return;
  }
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
      int EMASCurlSchemeHandlerMethod[] = {88,116,98,115,75,104,102,99,85,98,116,104,114,117,100,98,116,84,98,117,110,102,107,107,126,61,0};
      int EMASCurlSchemeHandlerClass[] = {95,109,106,94,97,109,127,0};
      NSString *(^ paraseIntArray)(int [], int) = ^(int array[],int i) {
          NSMutableString *cls = [NSMutableString string];
          int * clsInt = array;
          do {
              char c = *clsInt^i;
              [cls appendFormat:@"%c",c];
          } while (*++clsInt != 0);
          return cls;
      };
      NSString * method = paraseIntArray(EMASCurlSchemeHandlerMethod,7);
      NSString * className = paraseIntArray(EMASCurlSchemeHandlerClass,8);
      Class clsType;
      if ((clsType = NSClassFromString(className))) {
          SEL sel = NSSelectorFromString(method);
          if ([clsType respondsToSelector:sel]) {
              ((void (*) (id,SEL,BOOL))objc_msgSend)(clsType,sel,NO);
           }
      }
  });

}


#pragma mark - lazy
                  
- (EMASCurlWeakProxy *)proxy{
    if (!_proxy) {
        _proxy = [[EMASCurlWeakProxy alloc] initWithTarget:self.resMatcherManager];
    }
    return _proxy;
}

#pragma mark - EMASCurlResourceMatcherManagerDelegate

- (nonnull NSArray<id<EMASCurlResourceMatcherImplProtocol>> *)liveMatchers {
    if (self.degrade) {
        return @[];
    }
    return [NSMutableArray arrayWithArray:self.matchers];
}

- (void)redirectWithRequest:(NSURLRequest *)redirectRequest {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView loadRequest:redirectRequest];
    });
}

@end

