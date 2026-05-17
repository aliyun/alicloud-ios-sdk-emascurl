//
//  EMASCurlCookieStorage.m
//  EMASCurl
//
//  Created by xuyecan on 2025/2/3.
//

#import "EMASCurlCookieStorage.h"

@implementation EMASCurlCookieStorage

+ (instancetype)sharedStorage {
    static EMASCurlCookieStorage *sharedStorage = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedStorage = [[self alloc] init];
    });
    return sharedStorage;
}

- (instancetype)init {
    self = [super init];
    return self;
}

#pragma mark - Public Methods

- (void)setCookieWithString:(NSString *)cookieString forURL:(NSURL *)url {
    if (!cookieString.length || !url) {
        return;
    }

    // 解析 Set-Cookie 字符串并设置到 NSHTTPCookieStorage
    NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:@{@"Set-Cookie": cookieString} forURL:url];
    [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies:cookies forURL:url mainDocumentURL:nil];
}

- (NSString *)cookieStringForURL:(NSURL *)url {
    if (!url) {
        return nil;
    }

    NSArray<NSHTTPCookie *> *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url];
    NSDictionary *headers = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
    return headers[@"Cookie"];
}

@end
