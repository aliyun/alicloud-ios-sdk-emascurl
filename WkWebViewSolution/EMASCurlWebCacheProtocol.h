//
//  EMASCurlCacheProtocol.h

#import <WebKit/WebKit.h>
#import "EMASCurlWebConstant.h"

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(LimitVersion))
@protocol EMASCurlWebCacheProtocol <NSObject>

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key;

- (id<NSCoding>)objectForKey:(NSString *)key;

- (void)removeObjectForKey:(NSString *)key;

- (void)removeAllObjects;

@end

NS_ASSUME_NONNULL_END
