
#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

#define xURLSchemeHandlerKey "xURLSchemeHandlerKey"

#define EMASCurlValidStr(str) [EMASCurlWebUtils isValidStr:str]
#define EMASCurlWeak(v) __weak typeof(v) weak##v = v;
#define EMASCurlStrong(v) __strong typeof(weak##v) v = weak##v;

@interface EMASCurlWebUtils : NSObject

+ (BOOL)isValidStr:(NSString *)str;

+ (BOOL)isEqualURLA:(NSString *)urlStrA withURLB:(NSString *)urlStrB;

@end

@interface EMASCurlSafeArray <ObjectType>: NSObject<NSCopying>

- (instancetype)init;
- (NSUInteger)count;
- (void)addObject:(ObjectType)anObject;
- (void)removeObject:(ObjectType)anObject;

@end

@interface EMASCurlSafeDictionary <KeyType,ObjectType> : NSObject<NSCopying>

- (void)removeObjectForKey:(KeyType)aKey;
- (void)setObject:(ObjectType)anObject forKey:(KeyType <NSCopying>)aKey;
- (nullable ObjectType)objectForKey:(KeyType)aKey;

@end

@interface EMASCurlWebWeakProxy : NSProxy

- (instancetype)initWithObject:(id)object;

@end

NS_ASSUME_NONNULL_END
