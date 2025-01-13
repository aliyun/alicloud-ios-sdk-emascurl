//
//  EMASCurlSafeDictionary.m

#import "EMASCurlSafeDictionary.h"
#import <pthread.h>

#define EMASCurlSafeDictionaryLock(v,...)\
pthread_mutex_lock(&_lock);\
__VA_ARGS__;\
pthread_mutex_unlock(&_lock);\
return v;


@implementation EMASCurlSafeDictionary{
    pthread_mutex_t _lock;
    pthread_mutexattr_t _attr;
    NSMapTable * _dicM;
}

+ (instancetype)weakObjects{
    return [[self alloc] initWithWeak:YES];
}

+ (instancetype)strongObjects{
    return [[self alloc] initWithWeak:NO];
}

- (instancetype)initWithWeak:(BOOL)isWeak{
    if (self = [super init]) {
        if (isWeak) {
            _dicM = [NSMapTable strongToWeakObjectsMapTable];
        }else{
            _dicM = [NSMapTable strongToStrongObjectsMapTable];
        }
        pthread_mutexattr_init(&_attr);
        pthread_mutexattr_settype(&_attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_lock, &_attr);
    }
    return self;
}

- (instancetype)init
{
    return [EMASCurlSafeDictionary strongObjects];
}

- (void)removeObjectForKey:(id)aKey{
    if (aKey!=nil) {
        EMASCurlSafeDictionaryLock(, [_dicM removeObjectForKey:aKey])
    }
}
- (void)setObject:(id)anObject forKey:(id)aKey{
    if (anObject == nil) return;
    EMASCurlSafeDictionaryLock(,[_dicM setObject:anObject forKey:aKey])
}
- (void)removeAllObjects{
    EMASCurlSafeDictionaryLock(,[_dicM removeAllObjects])
}
- (void)addEntriesFromDictionary:(NSDictionary *)otherDictionary{
    if (![otherDictionary isKindOfClass:[NSDictionary class]]) return;
    EMASCurlSafeDictionaryLock(,[otherDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [_dicM setObject:obj forKey:key];
    }])
}
- (NSDictionary *)dictionary{
    id obj;
    EMASCurlSafeDictionaryLock(obj,obj = _dicM.dictionaryRepresentation);
}

- (NSArray *)allKeys{
    id obj;
    EMASCurlSafeDictionaryLock(obj,obj = [_dicM.dictionaryRepresentation allKeys]);
}

- (NSArray *)allValues{
    id obj;
    EMASCurlSafeDictionaryLock(obj,obj = [_dicM.dictionaryRepresentation allValues]);
}

- (NSInteger)count{
    NSInteger count;
    EMASCurlSafeDictionaryLock(count,count = [_dicM.dictionaryRepresentation count]);
}

- (NSArray *)allKeysForObject:(id)anObject{
    id obj;
    EMASCurlSafeDictionaryLock(obj,obj = [_dicM.dictionaryRepresentation allKeysForObject:anObject])
}

- (id)objectForKey:(id)aKey{
    id obj;
    EMASCurlSafeDictionaryLock(obj,obj = [_dicM objectForKey:aKey])
}

- (nullable id)objectForKeyedSubscript:(id)key{
    return [self objectForKey:key];
}
- (void)setObject:(nullable id)obj forKeyedSubscript:(id)key{
    [self setObject:obj forKey:key];
}
- (void)enumerateKeysAndObjectsUsingBlock:(void (NS_NOESCAPE ^)(id key, id obj, BOOL *stop))block{
    [self enumerateKeysAndObjectsWithOptions:NSEnumerationConcurrent usingBlock:block];
}
- (void)enumerateKeysAndObjectsWithOptions:(NSEnumerationOptions)opts usingBlock:(void (NS_NOESCAPE ^)(id key, id obj, BOOL *stop))block{
    EMASCurlSafeDictionaryLock(, [_dicM.dictionaryRepresentation enumerateKeysAndObjectsWithOptions:opts usingBlock:block])
}
- (id)copyWithZone:(NSZone *)zone{
    return self.dictionary;
}
- (void)dealloc
{
    pthread_mutexattr_destroy(&_attr);
    pthread_mutex_destroy(&_lock);
}
@end
#undef EMASCurlSafeDictionaryLock
