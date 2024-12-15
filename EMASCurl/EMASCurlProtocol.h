//
//  EMASCurlProtocol.h
//  EMASCurl
//
//  Created by xin yu on 2024/10/29.
//

#ifndef EMASCurlProtocol_h
#define EMASCurlProtocol_h

#import <Foundation/Foundation.h>

@protocol EMASCurlProtocolDNSResolver <NSObject>

+ (NSString *)resolveDomain:(NSString *)domain;

@end

typedef NS_ENUM(NSInteger, HTTPVersion) {
    HTTP1,
    HTTP2,
    HTTP3
};

@interface EMASCurlProtocol : NSURLProtocol

// 拦截使用自定义NSURLSessionConfiguration创建的session发起的requst
+ (void)installIntoSessionConfiguration:(NSURLSessionConfiguration*)sessionConfiguration;

// 拦截sharedSession发起的request
+ (void)registerCurlProtocol;

// 注销对sharedSession的拦截
+ (void)unregisterCurlProtocol;

+ (void)setHTTPVersion:(HTTPVersion)version;

+ (void)setSelfSignedCAFilePath:(NSString *)selfSignedCAFilePath;

+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled;

+ (void)setDNSResolver:(Class<EMASCurlProtocolDNSResolver>)resolver;

@end

#endif /* EMASCurlProtocol_h */
