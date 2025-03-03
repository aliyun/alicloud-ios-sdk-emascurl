//
//  EMASCurlHybridURLCache.h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlWebURLResponseCache : NSObject

- (void)cacheWithHTTPURLResponse:(NSHTTPURLResponse *)response
                            data:(NSData *)data
                         request:(NSURLRequest *)request;

- (nullable NSCachedURLResponse *)getCachedResponseWithRequest:(NSURLRequest *)request;

- (nullable NSCachedURLResponse *)updateCachedResponseWithURLResponse:(NSHTTPURLResponse *)newResponse
                                                              request:(NSURLRequest *)request;

@end

NS_ASSUME_NONNULL_END
