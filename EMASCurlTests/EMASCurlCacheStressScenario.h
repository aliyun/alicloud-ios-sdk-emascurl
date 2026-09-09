// Shared by opt-in XCTest and the simulator/device validation app.
// Uses normal public cache operations; no fault injection or private Foundation API.
#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import "EMASCurlResponseCache.h"

static NSDictionary *EMASRunCacheStress(NSUInteger iterations, BOOL update304) {
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                                 isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURLCache *backing;
    if (@available(iOS 13.0, *)) {
        backing = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:0 directoryURL:directory];
    } else {
        backing = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:0 diskPath:directory.path];
    }
    EMASCurlResponseCache *cache = [EMASCurlResponseCache new];
    [cache setValue:backing forKey:@"urlCache"];
    NSData *body = [@"0123456789abcdef" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray<NSURLRequest *> *requestBuilder = [NSMutableArray array];
    NSMutableArray<NSHTTPURLResponse *> *responseBuilder = [NSMutableArray array];
    for (NSUInteger i = 0; i < 8; i++) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://cache-stress.invalid/%lu", (unsigned long)i]];
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                             headerFields:@{@"Cache-Control": @"max-age=3600", @"ETag": @"\"seed\"", @"Content-Length": @"16"}];
        [requestBuilder addObject:request];
        [responseBuilder addObject:response];
        [cache cacheResponse:response data:body forRequest:request withHTTPVersion:@"HTTP/1.1"];
    }
    NSArray<NSURLRequest *> *requests = [requestBuilder copy];
    NSArray<NSHTTPURLResponse *> *responses = [responseBuilder copy];
    __block atomic_ulong sdkReturns = 0;
    __block atomic_ulong clientDeliveries = 0;
    __block atomic_ulong updateReturns = 0;
    __block atomic_ulong updateDeliveries = 0;
    __block atomic_ulong mismatches = 0;
    dispatch_queue_t workers = dispatch_queue_create("cache.validation.workers", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t producers = dispatch_group_create();
    dispatch_group_t consumers = dispatch_group_create();
    NSTimeInterval start = [NSProcessInfo processInfo].systemUptime;

    // Each reader hands the response to its own serial callback queue. The
    // callback waits until the reader's local pool has drained before using it.
    // At most 16 callbacks per producer are outstanding, so memory is bounded.
    for (NSUInteger reader = 0; reader < 2; reader++) {
        dispatch_queue_t client = dispatch_queue_create("cache.validation.client", DISPATCH_QUEUE_SERIAL);
        dispatch_semaphore_t slots = dispatch_semaphore_create(16);
        dispatch_group_async(producers, workers, ^{
            for (NSUInteger i = 0; i < iterations; i++) {
                dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
                dispatch_semaphore_t ready = dispatch_semaphore_create(0);
                @autoreleasepool {
                    NSCachedURLResponse *got = [cache cachedResponseForRequest:requests[(i + reader) % requests.count]];
                    if (got) atomic_fetch_add_explicit(&sdkReturns, 1, memory_order_relaxed);
                    dispatch_group_async(consumers, client, ^{
                        dispatch_semaphore_wait(ready, DISPATCH_TIME_FOREVER);
                        @autoreleasepool {
                            if (!got || ![got.data isEqualToData:body] || ((NSHTTPURLResponse *)got.response).statusCode != 200) {
                                atomic_fetch_add_explicit(&mismatches, 1, memory_order_relaxed);
                            }
                            atomic_fetch_add_explicit(&clientDeliveries, 1, memory_order_relaxed);
                        }
                        dispatch_semaphore_signal(slots);
                    });
                }
                dispatch_semaphore_signal(ready);
            }
        });
    }
    dispatch_queue_t updateClient = dispatch_queue_create("cache.validation.updateClient", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t updateSlots = dispatch_semaphore_create(16);
    dispatch_group_async(producers, workers, ^{
        for (NSUInteger i = 0; i < iterations; i++) {
            if (update304) dispatch_semaphore_wait(updateSlots, DISPATCH_TIME_FOREVER);
            dispatch_semaphore_t ready = dispatch_semaphore_create(0);
            @autoreleasepool {
                NSUInteger index = i % requests.count;
                if (update304) {
                    NSCachedURLResponse *updated = [cache updateCachedResponseWithHeaders:@{@"Cache-Control": @"max-age=3600", @"ETag": @"\"updated\""}
                                                                                forRequest:requests[index]];
                    if (updated) atomic_fetch_add_explicit(&updateReturns, 1, memory_order_relaxed);
                    dispatch_group_async(consumers, updateClient, ^{
                        dispatch_semaphore_wait(ready, DISPATCH_TIME_FOREVER);
                        @autoreleasepool {
                            NSHTTPURLResponse *response = (NSHTTPURLResponse *)updated.response;
                            NSString *etag = response.allHeaderFields[@"Etag"] ?: response.allHeaderFields[@"ETag"];
                            if (!updated || ![updated.data isEqualToData:body] || response.statusCode != 200 ||
                                ![etag isEqualToString:@"\"updated\""]) {
                                atomic_fetch_add_explicit(&mismatches, 1, memory_order_relaxed);
                            }
                            atomic_fetch_add_explicit(&updateDeliveries, 1, memory_order_relaxed);
                        }
                        dispatch_semaphore_signal(updateSlots);
                    });
                } else {
                    [cache cacheResponse:responses[index] data:body forRequest:requests[index] withHTTPVersion:@"HTTP/1.1"];
                }
            }
            dispatch_semaphore_signal(ready);
        }
    });
    dispatch_group_wait(producers, DISPATCH_TIME_FOREVER);
    dispatch_group_wait(consumers, DISPATCH_TIME_FOREVER);
    NSUInteger returns = atomic_load_explicit(&sdkReturns, memory_order_relaxed);
    NSUInteger deliveries = atomic_load_explicit(&clientDeliveries, memory_order_relaxed);
    NSUInteger updates = atomic_load_explicit(&updateReturns, memory_order_relaxed);
    NSUInteger updatedCallbacks = atomic_load_explicit(&updateDeliveries, memory_order_relaxed);
    NSUInteger errors = atomic_load_explicit(&mismatches, memory_order_relaxed);
    BOOL passed = returns == 2 * iterations && deliveries == 2 * iterations && errors == 0 &&
                  (!update304 || (updates == iterations && updatedCallbacks == iterations));
    return @{@"scenario": update304 ? @"304_two_readers" : @"store_two_readers", @"iterations_per_worker": @(iterations),
             @"readers": @2, @"keys": @8, @"memory_capacity": @(4 * 1024 * 1024), @"disk_capacity": @0,
             @"sdk_returned_responses": @(returns), @"client_deliveries": @(deliveries),
             @"304_returned_responses": @(updates), @"304_client_deliveries": @(updatedCallbacks),
             @"content_mismatches": @(errors), @"elapsed_seconds": @([NSProcessInfo processInfo].systemUptime - start),
             @"passed": @(passed)};
}
