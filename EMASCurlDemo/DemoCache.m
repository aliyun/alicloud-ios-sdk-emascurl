//
//  NetworkCache.m
//  EMASCurlDemo
//
//  Created by xuyecan on 2025/1/13.
//

#import "DemoCache.h"
#import <YYCache/YYCache.h>

@interface DemoCache ()

@property (nonatomic, strong) YYCache * cache;

@end

@implementation DemoCache

- (instancetype)initWithName:(NSString *)name
{
    self = [super init];
    if (self) {
        _cache = [YYCache cacheWithName:name];
    }
    return self;
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key {
    [_cache setObject:object forKey:key];
}

- (id <NSCoding>)objectForKey:(NSString *)key {
    return [_cache objectForKey:key];
}

- (void)removeObjectForKey:(NSString *)key {
    [_cache removeObjectForKey:key];
}

- (void)removeAllObjects {
    [_cache removeAllObjects];
}
@end
