
#import "EMASCurlWebUtils.h"
#import <pthread.h>

@implementation EMASCurlWebUtils

+ (BOOL)isValidStr:(NSString *)str {
    if (str == nil || ![str isKindOfClass:[NSString class]] || str.length == 0) {
        return NO;
    }
    return YES;
}

+ (BOOL)isEqualURLA:(NSString *)urlStrA withURLB:(NSString *)urlStrB {
    if (!urlStrA ||
        !urlStrB ||
        !EMASCurlValidStr(urlStrA) ||
        !EMASCurlValidStr(urlStrB)) {
        return NO;
    }

    if ([urlStrA isEqualToString:urlStrB]) {
        return YES;
    }
    NSCharacterSet *set = [NSCharacterSet characterSetWithCharactersInString:@"/ "];
    NSURL *urlA = [NSURL URLWithString:urlStrA];
    NSURL *urlB = [NSURL URLWithString:urlStrB];

    if (![urlA.scheme isEqualToString:urlB.scheme]) {
        return NO;
    }

    if (![urlA.host isEqualToString:urlB.host]) {
        return NO;
    }

    if (![[urlA.path stringByTrimmingCharactersInSet:set] isEqualToString:[urlB.path stringByTrimmingCharactersInSet:set]]) {
        return NO;
    }
    return YES;
}

@end


@interface EMASCurlSafeArray ()

@property (nonatomic, strong) NSMutableArray *array;
@property (nonatomic, assign) pthread_mutex_t mutex;

@end

@implementation EMASCurlSafeArray

- (instancetype)init {
    self = [super init];
    if (self) {
        _array = [[NSMutableArray alloc] init];
        pthread_mutex_init(&_mutex, NULL);
    }
    return self;
}

- (NSUInteger)count {
    NSUInteger count;
    pthread_mutex_lock(&_mutex);
    count = _array.count;
    pthread_mutex_unlock(&_mutex);
    return count;
}

- (void)addObject:(id)anObject {
    if (!anObject) {
        return;
    }
    pthread_mutex_lock(&_mutex);
    [_array addObject:anObject];
    pthread_mutex_unlock(&_mutex);
}

- (void)removeObject:(id)anObject {
    if (!anObject) {
        return;
    }
    pthread_mutex_lock(&_mutex);
    [_array removeObject:anObject];
    pthread_mutex_unlock(&_mutex);
}

- (id)copyWithZone:(NSZone *)zone {
    EMASCurlSafeArray *copy = [[[self class] allocWithZone:zone] init];
    pthread_mutex_lock(&_mutex);
    copy->_array = [_array mutableCopy];
    pthread_mutex_unlock(&_mutex);
    return copy;
}

- (void)dealloc {
    pthread_mutex_destroy(&_mutex);
}

@end


@interface EMASCurlSafeDictionary ()

@property (nonatomic, strong) NSMutableDictionary *dictionary;
@property (nonatomic, assign) pthread_mutex_t mutex;

@end

@implementation EMASCurlSafeDictionary

- (instancetype)init {
    self = [super init];
    if (self) {
        _dictionary = [[NSMutableDictionary alloc] init];
        pthread_mutex_init(&_mutex, NULL);
    }
    return self;
}

- (void)setObject:(id)anObject forKey:(id<NSCopying>)aKey {
    if (!aKey) {
        return;
    }
    pthread_mutex_lock(&_mutex);
    if (anObject) {
        [_dictionary setObject:anObject forKey:aKey];
    } else {
        [_dictionary removeObjectForKey:aKey];
    }
    pthread_mutex_unlock(&_mutex);
}

- (void)removeObjectForKey:(id)aKey {
    if (!aKey) {
        return;
    }
    pthread_mutex_lock(&_mutex);
    [_dictionary removeObjectForKey:aKey];
    pthread_mutex_unlock(&_mutex);
}

- (id)objectForKey:(id)aKey {
    if (!aKey) {
        return nil;
    }
    id result = nil;
    pthread_mutex_lock(&_mutex);
    result = [_dictionary objectForKey:aKey];
    pthread_mutex_unlock(&_mutex);
    return result;
}

- (id)copyWithZone:(NSZone *)zone {
    EMASCurlSafeDictionary *copy = [[[self class] allocWithZone:zone] init];
    pthread_mutex_lock(&_mutex);
    copy->_dictionary = [_dictionary mutableCopy];
    pthread_mutex_unlock(&_mutex);
    return copy;
}

- (void)dealloc {
    pthread_mutex_destroy(&_mutex);
}

@end


@interface EMASCurlWebWeakProxy ()

@property (nonatomic, weak) id theObject;

@end


@implementation EMASCurlWebWeakProxy

- (instancetype)initWithObject:(id)object {
    _theObject = object;
    return self;
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    return self.theObject;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    id object = self.theObject;
    if (object) {
        return [object methodSignatureForSelector:aSelector];
    } else {
        return [NSMethodSignature signatureWithObjCTypes:"v@:"];
    }
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    [anInvocation invokeWithTarget:self.theObject];
}

@end
