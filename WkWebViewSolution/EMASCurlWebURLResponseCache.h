//
//  EMASCurlHybridURLCache.h

#import <Foundation/Foundation.h>
#import "EMASCurlWebURLResponse.h"
#import "EMASCurlWebCacheProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlWebURLResponseCache : NSObject

- (instancetype)initWithDelegate:(id<EMASCurlWebCacheProtocol>)delegate;

- (void)cacheWithHTTPURLResponse:(NSHTTPURLResponse *)response
                            data:(NSData *)data
                             url:(NSString *)url ;

- (nullable EMASCurlWebURLResponse *)getCachedResponseWithURL:(NSString *)url ;

- (nullable EMASCurlWebURLResponse *)updateCachedResponseWithURLResponse:(NSHTTPURLResponse *)newResponse
                                                           requestUrl:(NSString *)url;

- (void)clear;

@end

NS_ASSUME_NONNULL_END
