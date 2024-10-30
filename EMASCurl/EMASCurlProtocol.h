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

@interface EMASCurlProtocol : NSURLProtocol

+ (void)installIntoSessionConfiguration:(NSURLSessionConfiguration*)sessionConfiguration;

+ (void)registerCurlProtocol;

+ (void)unregisterCurlProtocol;

+ (void)activateHttp2;

+ (void)activateHttp3;

+ (void)setDebugLogEnabled:(BOOL)debugLogEnabled;

+ (void)setDNSResolver:(Class<EMASCurlProtocolDNSResolver>)resolver;

@end

#endif /* EMASCurlProtocol_h */
