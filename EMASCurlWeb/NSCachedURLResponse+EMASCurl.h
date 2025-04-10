#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSCachedURLResponse (EMASCurl)

- (BOOL)emas_canCache;

- (BOOL)emas_isExpired;

- (nullable NSString *)emas_etag;

- (nullable NSString *)emas_lastModified;

- (NSCachedURLResponse *)emas_updatedResponseWithHeaderFields:(NSDictionary *)newHeaderFields;

+ (nullable NSCachedURLResponse *)emas_cachedResponseWithResponse:(NSHTTPURLResponse *)response
                                                            data:(NSData *)data
                                                            url:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END