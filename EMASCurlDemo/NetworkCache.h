//
//  NetworkCache.h
//  EMASCurlDemo
//
//  Created by xuyecan on 2025/1/13.
//

#import <Foundation/Foundation.h>
#import <EMASCurl/EMASCurl.h>

NS_ASSUME_NONNULL_BEGIN

@interface NetworkCache : NSObject<JDURLCacheDelegate>

- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
