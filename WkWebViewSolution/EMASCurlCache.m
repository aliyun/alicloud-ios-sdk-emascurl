//
//  EMASCurlCache.m

#import <Foundation/Foundation.h>
#import "EMASCurlCache.h"
#import "EMASCurlUtils.h"

@implementation EMASCurlCache

+ (EMASCurlCache *)shareInstance{
    static EMASCurlCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [EMASCurlCache new];
    });
    return cache;
}

- (void)setLogEnabled:(BOOL)logEnabled {
    [EMASCurlUtils setLogEnable:logEnabled];
}

@end
