//
//  EMASCurlWkWebViewContentLoader.m
//  EMASCurl
//
//  Created by xuyecan on 2025/2/4.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import "EMASCurlWebUrlSchemeHandler.h"
#import "EMASCurlWebContentLoader.h"
#import "EMASCurlWebLogger.h"
#import "EMASCurlWebUtils.h"

static void *kEMASCurlStoreConfigurationKey = &kEMASCurlStoreConfigurationKey;

@implementation EMASCurlWebContentLoader

+ (void)initializeInterception {
    [self swizzleWkWebViewMethod];
    [self swizzleWkWebViewConfigurationMethod];
}

+ (void)setDebugLogEnabled:(BOOL)enabled {
    [EMASCurlWebLogger setDebugLogEnabled:enabled];
}

+ (void)swizzleWkWebViewMethod {
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
                method_setImplementation(method, newImp);
            }
        }
        {
            __block WKWebView* (*oldImp)(id,SEL,CGRect,id)  = NULL;
            SEL sel = @selector(initWithFrame:configuration:);
            IMP newImp = imp_implementationWithBlock(^(id obj, CGRect frame, WKWebViewConfiguration*configuration){
                WKWebView *webview = oldImp(obj, sel, frame, configuration);
                objc_setAssociatedObject(webview, kEMASCurlStoreConfigurationKey, configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [configuration setWkWebView:webview];
                return webview;
            });
            Method method = class_getInstanceMethod(cls, sel);
            oldImp = (WKWebView* (*)(id, SEL, CGRect, id))method_getImplementation(method);
            if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(method))) {
                oldImp = (WKWebView* (*)(id, SEL, CGRect, id))method_setImplementation(method, newImp);
            }
        }
    });
}

+ (void)swizzleWkWebViewConfigurationMethod {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [WKWebViewConfiguration class];
        __block void * (*oldImp)(id, SEL, id, id) = NULL;
        SEL sel = @selector(setURLSchemeHandler:forURLScheme:);
        IMP newImp = imp_implementationWithBlock(^(id obj, id<WKURLSchemeHandler> schemeHandler, NSString *scheme) {
            oldImp(obj, sel, schemeHandler, scheme);
            void *storeKey = (__bridge  void*)[EMASCurlWebUrlSchemeHandler class];
            EMASCurlWebWeakProxy *redirectDelegateProxy = [[EMASCurlWebWeakProxy alloc] initWithObject:obj];
            objc_setAssociatedObject(schemeHandler, storeKey, redirectDelegateProxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
        Method method = class_getInstanceMethod(cls, sel);
        oldImp = (void * (*)(id, SEL, id, id))method_getImplementation(method);
        if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(method))) {
            method_setImplementation(method, newImp);
        }
    });
}

@end
