//
//  EMASCurlHybridURLCache.h

#import <Foundation/Foundation.h>
#import "EMASCurlCachedURLResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlURLCache : NSObject

+ (instancetype)defaultCache;

- (instancetype)initWithCacheName:(NSString *)cacheName;

- (void)cacheWithHTTPURLResponse:(NSHTTPURLResponse *)response
                            data:(NSData *)data
                             url:(NSString *)url ;

- (nullable EMASCurlCachedURLResponse *)getCachedResponseWithURL:(NSString *)url ;

- (nullable EMASCurlCachedURLResponse *)updateCachedResponseWithURLResponse:(NSHTTPURLResponse *)newResponse
                                                           requestUrl:(NSString *)url;

- (void)clear;

@end

NS_ASSUME_NONNULL_END
