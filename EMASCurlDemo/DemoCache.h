//
//  NetworkCache.h
//  EMASCurlDemo
//
//  Created by xuyecan on 2025/1/13.
//

#import <Foundation/Foundation.h>
#import <EMASCurl/EMASCurl.h>
#import <EMASCurlWeb/EMASCurlWeb.h>

NS_ASSUME_NONNULL_BEGIN

@interface DemoCache : NSObject<EMASCurlWebCacheProtocol>

- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
