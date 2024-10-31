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

+ (void)installIntoSessionConfiguration:(NSURLSessionConfiguration*)sessionConfiguration;

+ (void)registerCurlProtocol;

+ (void)unregisterCurlProtocol;

+ (void)setHTTPVersion:(HTTPVersion)version;

+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled;

+ (void)setDNSResolver:(Class<EMASCurlProtocolDNSResolver>)resolver;

@end

#endif /* EMASCurlProtocol_h */
