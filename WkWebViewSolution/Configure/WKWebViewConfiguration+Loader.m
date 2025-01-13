//
//  WKWebViewConfiguration+Loader.m
//  EMASCurlHybrid
/*
 MIT License

Copyright (c) 2022 EMASCurl.com, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

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
