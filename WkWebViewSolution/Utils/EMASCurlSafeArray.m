//
//  EMASCurlSafeArray.m

#import "EMASCurlSafeArray.h"
#import <pthread.h>

#define EMASCurlSafeArrayLock(v,...)\
pthread_mutex_lock(&_lock);\
[_arrM addPointer:nil];\
[_arrM compact];\
__VA_ARGS__;\
pthread_mutex_unlock(&_lock);\
return v;

@implementation EMASCurlSafeArray{
    pthread_mutex_t _lock;
    pthread_mutexattr_t _attr;
    NSPointerArray * _arrM;
}

+ (instancetype)weakObjects{
    return [[self alloc] initWithWeak:YES];
}

+ (instancetype)strongObjects{
    return [[self alloc] initWithWeak:NO];
}

- (instancetype)initWithWeak:(BOOL)isWeak
{
    self = [super init];
    if (self) {
        if (isWeak) {
            _arrM = [[NSPointerArray alloc] initWithOptions:NSPointerFunctionsWeakMemory];
        }else{
            _arrM = [[NSPointerArray alloc] initWithOptions:NSPointerFunctionsStrongMemory];
        }
        pthread_mutexattr_init(&_attr);
        pthread_mutexattr_settype(&_attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_lock, &_attr);
    }
    return self;
}

- (instancetype)init{
    return [EMASCurlSafeArray strongObjects];
}


- (NSUInteger)count{
    NSInteger count;
    EMASCurlSafeArrayLock(count,count=_arrM.count)
}

- (BOOL)containsObject:(id)anObject{
    if (anObject == nil) return NO;
    BOOL isContain;
    EMASCurlSafeArrayLock(isContain,isContain=[[_arrM allObjects] containsObject:anObject])
}

- (nullable id)objectAtIndex:(NSUInteger)index{
    if (index < 0 || index >= self.count) return nil;
    id obj;
    EMASCurlSafeArrayLock(obj,obj=[_arrM pointerAtIndex:index])
}

- (id)objectAtIndexedSubscript:(NSUInteger)idx{
    return [self objectAtIndex:idx];
}

- (void)addObjectsFromArray:(NSArray<id> *)otherArray{
    if (![otherArray isKindOfClass:[NSArray class]]) {
        return;
    }
    EMASCurlSafeArrayLock(,NO,[otherArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [_arrM addPointer:(__bridge void *)obj];
    }])
}

- (void)removeAllObjects{
    EMASCurlSafeArrayLock(,while(_arrM.count > 0){
        [_arrM removePointerAtIndex:0];
    })
}

- (void)addObject:(id)anObject{
    if (anObject == nil) return;
    EMASCurlSafeArrayLock(,[_arrM addPointer:(__bridge void *)anObject])
}

- (void)insertObject:(id)anObject atIndex:(NSUInteger)index{
    if (anObject == nil || index < 0 || index >= self.count) return;
    EMASCurlSafeArrayLock(,[_arrM insertPointer:(__bridge void *)anObject atIndex:index])
}

- (void)removeLastObject{
    [self removeObjectAtIndex:self.count-1];
}

- (void)removeObjectAtIndex:(NSUInteger)index{
    if (index < 0 || index >= self.count) return;
    EMASCurlSafeArrayLock(,[_arrM removePointerAtIndex:index])
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject{
    if (anObject == nil || index < 0 || index >= self.count) return;
    EMASCurlSafeArrayLock(,[_arrM replacePointerAtIndex:index withPointer:(__bridge void *)anObject])
}

- (void)removeObject:(id)anObject{
    if (anObject == nil) return;
    EMASCurlSafeArrayLock(,
                    NSInteger index = [_arrM.allObjects indexOfObject:anObject];
                    if(index != NSNotFound){
                        [_arrM removePointerAtIndex:index];
    }
                    )
}

- (void)enumerateObjectsUsingBlock:(void (NS_NOESCAPE ^)(id obj, NSUInteger idx, BOOL *stop))block{
    [self enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:block];
}

- (void)enumerateObjectsWithOptions:(NSEnumerationOptions)opts usingBlock:(void (NS_NOESCAPE ^)(id obj, NSUInteger idx, BOOL *stop))block{
    EMASCurlSafeArrayLock(,BOOL stop = NO;
                    NSInteger count = self.count - 1;
                    NSArray *allObjs = _arrM.allObjects;
                    for (NSInteger i = 0; i < self.count; i++) {
                        NSInteger realIndex = opts == NSEnumerationConcurrent?i:count-i;
                        block(allObjs[realIndex],realIndex,&stop);
                        if (stop) {
                            break;
                        }
    })
}



- (NSArray *)values{
    NSArray *array;
    EMASCurlSafeArrayLock(array,array=_arrM.allObjects)
}

- (NSUInteger)indexOfObject:(id)anObject{
    if (!anObject) {
        return NSNotFound;
    }
    NSInteger index;
    EMASCurlSafeArrayLock(index,index = [_arrM.allObjects indexOfObject:anObject]);
}

- (void)dealloc
{
    pthread_mutexattr_destroy(&_attr);
    pthread_mutex_destroy(&_lock);
}

- (id)copyWithZone:(NSZone *)zone{
    return self.values;
}

@end
#undef EMASCurlSafeArrayLock
