//
//  EMASCurlCacheUAFTest.m
//  EMASCurlTests
//
//  复现目标（客户现场，iOS 26.1）：
//    0  -[NSCachedURLResponse _reestablishInternalCFCachedURLResponse:] + 8
//    1  -[NSURLCache cachedResponseForRequest:] + 84
//    2  EMASCurlResponseCache.m:100        （线程 queue: com.alicloud.emascurl.cacheQueue）
//
//  机制（以 CFNetwork 反汇编为依据，非本文件的运行时观测所能证明）：
//    __CFCachedURLResponse 在 +0x68 保存一个不执行 retain 的 ObjC wrapper 裸指针，
//    读取/清除由 +0x58 处的 os_unfair_lock 保护。真正的窗口是：
//    wrapper 的最后一次 release 已使其进入 dealloc，但 dealloc 尚未取得锁清除反向指针，
//    此时另一线程经反向指针取出该对象并 objc_retain，从而拿到正在析构/已失效的对象。
//
//  本次落地的是 cacheQueue 内的局部 autoreleasepool，只修复部分临时对象释放竞态。
//  lookup / 304 返回对象在调用方释放，以及外部组件访问 sharedURLCache 的窗口仍未覆盖。
//  独占缓存与返回脱钩副本属于不同的候选方案；外部共写下副本仍崩，不能否定它对返回路径的作用。
//  分组参数、实际结果和环境见 README.md 及 CacheValidationResults.md；无崩溃不等于消除窗口。
//  自动功能回归在 EMASCurlCacheRegressionTest；可选择运行的正常并发场景在 EMASCurlCacheStressTest。
//
//  证明力分级（不要混用）：
//    A. 证据组 uafGroupN_*   —— 唯一变量对照，用于支撑因果结论
//    B. 诊断组 uafDiagnose*  —— 仅提供运行时观测量，不单独构成证明
//    C. 注入组 uafFault*     —— 故障注入，仅演示寄存器/指令关系，不代表真实触发路径
//
//  本文件保留 uaf 前缀的历史诊断实验，默认不进入 xcodebuild test / CI。
//  它们用于记录特定负载下是否发生崩溃；不要求旧版必须崩溃，也不以新版无崩证明完整修复。
//
//  并发输入一律使用不可变对象（NSURLRequest / NSArray），每次操作取 request 副本，
//  避免可变对象成为干扰变量。
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdatomic.h>
#import "EMASCurlResponseCache.h"
#import "EMASCurlCacheConstants.h"

#pragma mark - 压力参数

static const int kEMASUAFURLCount = 8;        // 少量缓存键，制造同键碰撞（现场同一 URL 在 0.6s 内被请求 3 次）
static const int kEMASUAFIterations = 60000;  // 将毫秒级窗口累积到可观测
static const int kEMASUAFExternalThreads = 3;

#pragma mark - 辅助类型

/// 判别器：仅用于读取 isa 判断 lookup 返回对象的身份，不写内存。
@interface EMASUAFProbe : NSCachedURLResponse
@end
@implementation EMASUAFProbe
@end

/// 与 NSCachedURLResponse 实例同尺寸（isa 8 + slot 8 = 16）的占位对象，
/// _slot 落在 offset 0x8，即 NSCachedURLResponse 的 _internal 字段位置。
@interface EMASUAFFiller : NSObject
- (void)poison;
@end
@implementation EMASUAFFiller {
    void *_slot;
}
- (void)poison {
    _slot = (void *)0xd001;
}
@end

#pragma mark - 辅助函数

/// 诊断输出同时落盘：XCTest 进程的 stdout 不一定被 xcodebuild 捕获，
/// 且崩溃场景下需要凭「有 start 无 survived」判定进程是否死亡。
static void EMASUAFLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSLog(@"[UAF] %@", msg);
    fprintf(stderr, "[UAF] %s\n", msg.UTF8String);
    fflush(stderr);

    FILE *sink = fopen("/tmp/emascurl-uaf.log", "a");
    if (sink) {
        fprintf(sink, "[UAF] %s\n", msg.UTF8String);
        fclose(sink);
    }
}

/// 通过 objc_msgSend 直接取回 C 指针，避免 ARC 把非 ObjC 对象当 id 处理。
static void *EMASUAFInternalCFResponse(NSCachedURLResponse *response) {
    SEL sel = sel_registerName("_CFCachedURLResponse");
    if (![response respondsToSelector:sel]) {
        return (void *)-1;
    }
    typedef void *(*Fn)(id, SEL);
    return ((Fn)objc_msgSend)(response, sel);
}

/// 不可路由的保留 TLD，确保任何代码路径都不会发起真实网络请求。
static NSURLRequest *EMASUAFRequest(NSString *path) {
    NSString *urlString = [NSString stringWithFormat:@"https://uaf-repro.invalid/%@", path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"GET";
    return [request copy];
}

/// 并发输入用不可变数组承载不可变 request。
static NSArray<NSURLRequest *> *EMASUAFRequests(NSString *prefix) {
    NSMutableArray<NSURLRequest *> *requests = [NSMutableArray arrayWithCapacity:kEMASUAFURLCount];
    for (int i = 0; i < kEMASUAFURLCount; i++) {
        [requests addObject:EMASUAFRequest([NSString stringWithFormat:@"%@-%d.jpg", prefix, i])];
    }
    return [requests copy];
}

static NSHTTPURLResponse *EMASUAFResponse(NSURL *url, NSUInteger length) {
    return [[NSHTTPURLResponse alloc] initWithURL:url
                                       statusCode:200
                                      HTTPVersion:@"HTTP/1.1"
                                     headerFields:@{
        @"Content-Type": @"image/jpeg",
        @"Cache-Control": @"max-age=600",
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)length]
    }];
}

static NSData *EMASUAFBody(void) {
    return [@"0123456789abcdef" dataUsingEncoding:NSUTF8StringEncoding];
}

/// 拉齐共享实例与独占实例的容量，避免容量差异成为隐蔽变量。
static void EMASUAFAlignSharedCapacity(void) {
    NSURLCache *shared = [NSURLCache sharedURLCache];
    shared.memoryCapacity = 4 * 1024 * 1024;
    shared.diskCapacity = 32 * 1024 * 1024;
}

static void EMASUAFLogCapacity(NSString *tag, NSURLCache *cache) {
    EMASUAFLog(@"%@ capacity: memory=%lu disk=%lu", tag,
               (unsigned long)cache.memoryCapacity, (unsigned long)cache.diskCapacity);
}

/// initWithMemoryCapacity:diskCapacity:directoryURL: 是 iOS 13+ API，
/// 而测试 target 的 deployment target 为 iOS 11，故在此集中做一次可用性判断。
static NSURLCache *EMASUAFCacheAtDirectory(NSURL *directoryURL,
                                           NSUInteger memoryCapacity,
                                           NSUInteger diskCapacity) {
    if (@available(iOS 13.0, *)) {
        return [[NSURLCache alloc] initWithMemoryCapacity:memoryCapacity
                                            diskCapacity:diskCapacity
                                            directoryURL:directoryURL];
    }
    return [[NSURLCache alloc] initWithMemoryCapacity:memoryCapacity
                                        diskCapacity:diskCapacity
                                            diskPath:directoryURL.path];
}

/// 独占缓存实例必须使用独立目录，否则可能与 sharedURLCache 共用底层 CacheDB，
/// 造成「隔离」只是表象。
static NSURLCache *EMASUAFDedicatedCache(void) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"emas-uaf-%@", NSUUID.UUID.UUIDString]];
    NSURL *directoryURL = [NSURL fileURLWithPath:dir isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
    return EMASUAFCacheAtDirectory(directoryURL, 4 * 1024 * 1024, 32 * 1024 * 1024);
}

/// 向指定 NSURLCache 持续写入：构造 wrapper → store → 立即出 pool 释放。
/// 释放时机是竞态的一端，故每轮单独用 autoreleasepool 精确控制。
static void EMASUAFStoreLoop(NSURLCache *cache, NSArray<NSURLRequest *> *requests, int iterations) {
    NSData *body = EMASUAFBody();
    for (int n = 0; n < iterations; n++) {
        @autoreleasepool {
            NSURLRequest *request = [requests[n % requests.count] copy];
            NSCachedURLResponse *wrapper =
                [[NSCachedURLResponse alloc] initWithResponse:EMASUAFResponse(request.URL, body.length)
                                                        data:body
                                                    userInfo:@{EMASUserInfoKeyStorageTimestamp: @([NSDate date].timeIntervalSince1970)}
                                               storagePolicy:NSURLCacheStorageAllowed];
            [cache storeCachedResponse:wrapper forRequest:request];
        }
    }
}

/// 从指定 NSURLCache 持续读取。必须真实触碰返回对象，否则拿到悬空指针也不会解引用。
/// 返回 Foundation 命中次数。它与下方 SDK 返回计数的统计层不同，不能混作同一种命中率。
static int EMASUAFLookupLoop(NSURLCache *cache, NSArray<NSURLRequest *> *requests, int iterations) {
    int hits = 0;
    for (int n = 0; n < iterations; n++) {
        @autoreleasepool {
            NSURLRequest *request = [requests[n % requests.count] copy];
            NSCachedURLResponse *got = [cache cachedResponseForRequest:request];
            if (got) {
                hits++;
            }
            (void)got.response;
            (void)got.data.length;
        }
    }
    return hits;
}

/// 经 EMASCurlResponseCache 读取，返回 SDK 可用响应数，不代表底层 Foundation 命中次数。
static int EMASUAFEMASLookupLoop(EMASCurlResponseCache *cache, NSArray<NSURLRequest *> *requests, int iterations) {
    int hits = 0;
    for (int n = 0; n < iterations; n++) {
        @autoreleasepool {
            NSURLRequest *request = [requests[n % requests.count] copy];
            NSCachedURLResponse *got = [cache cachedResponseForRequest:request];
            if (got) {
                hits++;
            }
            (void)got.response;
            (void)got.data.length;
        }
    }
    return hits;
}

/// 经 EMASCurlResponseCache 写入（内部同样 dispatch_sync 到自己的串行队列）。
static void EMASUAFEMASStoreLoop(EMASCurlResponseCache *cache, NSArray<NSURLRequest *> *requests, int iterations) {
    NSData *body = EMASUAFBody();
    for (int n = 0; n < iterations; n++) {
        @autoreleasepool {
            NSURLRequest *request = [requests[n % requests.count] copy];
            [cache cacheResponse:EMASUAFResponse(request.URL, body.length)
                            data:body
                      forRequest:request
                 withHTTPVersion:@"HTTP/1.1"];
        }
    }
}

#pragma mark - 基准辅助（性能量化，非因果证明）

/// 单调时钟，避免系统时间调整影响测量。
static uint64_t EMASUAFNanos(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
}

static NSURLCache *EMASUAFCacheWithCapacity(NSUInteger memoryCapacity, NSUInteger diskCapacity) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"emas-bench-%@", NSUUID.UUID.UUIDString]];
    NSURL *directoryURL = [NSURL fileURLWithPath:dir isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
    return EMASUAFCacheAtDirectory(directoryURL, memoryCapacity, diskCapacity);
}

static NSArray<NSURLRequest *> *EMASUAFRequestsWithCount(NSString *prefix, int count) {
    NSMutableArray<NSURLRequest *> *requests = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [requests addObject:EMASUAFRequest([NSString stringWithFormat:@"%@-%d.jpg", prefix, i])];
    }
    return [requests copy];
}

static void EMASUAFFillCache(NSURLCache *cache, NSArray<NSURLRequest *> *requests, NSData *body) {
    for (NSURLRequest *request in requests) {
        @autoreleasepool {
            NSCachedURLResponse *wrapper =
                [[NSCachedURLResponse alloc] initWithResponse:EMASUAFResponse(request.URL, body.length)
                                                        data:body
                                                    userInfo:nil
                                               storagePolicy:NSURLCacheStorageAllowed];
            [cache storeCachedResponse:wrapper forRequest:request];
        }
    }
}

/// 「返回防御性副本」候选实现：只 retain 三个成员，不拷贝响应体。
static NSCachedURLResponse *EMASUAFDetachedCopy(NSCachedURLResponse *source) {
    if (!source) {
        return nil;
    }
    return [[NSCachedURLResponse alloc] initWithResponse:source.response
                                                   data:source.data
                                               userInfo:source.userInfo
                                          storagePolicy:source.storagePolicy];
}

typedef NS_ENUM(NSInteger, EMASUAFBenchMode) {
    /// 对应 EMASCurlProtocol.m:1151 条件请求路径：只读 response 头，从不触碰 .data
    EMASUAFBenchLookupOnly,
    /// 叠加防御性副本（副本构造必须读取 .data getter）
    EMASUAFBenchLookupCopy,
    /// 再叠加真实触碰响应体首字节，用于分辨 .data getter 是否惰性
    EMASUAFBenchLookupCopyTouch,
};

static uint64_t EMASUAFBenchRun(NSURLCache *cache,
                                NSArray<NSURLRequest *> *requests,
                                int ops,
                                EMASUAFBenchMode mode,
                                int *outHits) {
    int hits = 0;
    uint64_t start = EMASUAFNanos();
    for (int n = 0; n < ops; n++) {
        @autoreleasepool {
            NSURLRequest *request = [requests[n % requests.count] copy];
            NSCachedURLResponse *got = [cache cachedResponseForRequest:request];
            if (!got) {
                continue;
            }
            hits++;
            (void)got.response;
            if (mode == EMASUAFBenchLookupOnly) {
                continue;
            }
            NSCachedURLResponse *detached = EMASUAFDetachedCopy(got);
            if (mode == EMASUAFBenchLookupCopyTouch) {
                NSData *data = detached.data;
                volatile char first = data.length ? ((const char *)data.bytes)[0] : 0;
                (void)first;
            }
            (void)detached;
        }
    }
    uint64_t elapsed = EMASUAFNanos() - start;
    if (outHits) {
        *outHits = hits;
    }
    return elapsed;
}

/// 微基准的噪声是单边的（外部扰动只会让某轮变慢，不会变快），
/// 因此中位数比均值稳健，最小值最接近无扰动下的真实成本。
static double EMASUAFMedian(NSArray<NSNumber *> *samples) {
    if (samples.count == 0) {
        return 0;
    }
    NSArray<NSNumber *> *sorted = [samples sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger mid = sorted.count / 2;
    if (sorted.count % 2 == 1) {
        return sorted[mid].doubleValue;
    }
    return (sorted[mid - 1].doubleValue + sorted[mid].doubleValue) / 2.0;
}

static double EMASUAFMin(NSArray<NSNumber *> *samples) {
    double best = INFINITY;
    for (NSNumber *sample in samples) {
        best = MIN(best, sample.doubleValue);
    }
    return samples.count ? best : 0;
}

#pragma mark - 测试

@interface EMASCurlCacheUAFTest : XCTestCase
@end

@implementation EMASCurlCacheUAFTest

- (void)setUp {
    [super setUp];
    EMASUAFAlignSharedCapacity();
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

#pragma mark - A. 证据组（唯一变量对照）

/// 第一组：sharedURLCache + 纯 EMASCurl。
/// EMASCurlResponseCache 的 store 与 lookup 都经由自身的 DISPATCH_QUEUE_SERIAL，
/// 进程内不存在其他访问方，用于观察单写单读模型；不覆盖多 reader 交错释放返回对象。
- (void)uafGroup1_SharedCache_EMASCurlOnly {
    EMASCurlResponseCache *responseCache = [EMASCurlResponseCache new];
    NSArray<NSURLRequest *> *requests = EMASUAFRequests(@"g1");

    EMASUAFLog(@"G1 start: sharedURLCache + EMASCurl only, iterations=%d", kEMASUAFIterations);
    EMASUAFLogCapacity(@"G1 shared", [NSURLCache sharedURLCache]);

    dispatch_queue_t queue = dispatch_queue_create("uaf.g1", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_async(group, queue, ^{
        EMASUAFEMASStoreLoop(responseCache, requests, kEMASUAFIterations);
    });
    dispatch_group_async(group, queue, ^{
        int hits = EMASUAFEMASLookupLoop(responseCache, requests, kEMASUAFIterations);
        EMASUAFLog(@"G1 reader hits=%d/%d", hits, kEMASUAFIterations);
    });

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    EMASUAFLog(@"G1 survived");
}

/// 第一组变体 b：EMASCurl 使用独占 NSURLCache，且进程内无任何外部访问方。
/// 用于判定竞态是否内生于「store 后释放 wrapper，随后 lookup」这一自身序列。
/// 若本组崩溃，只能说明独占实例本身不足以消除所测内部窗口。
- (void)uafGroup1b_DedicatedCache_EMASCurlOnly {
    EMASCurlResponseCache *responseCache = [EMASCurlResponseCache new];
    NSURLCache *dedicated = EMASUAFDedicatedCache();
    [responseCache setValue:dedicated forKey:@"urlCache"];
    XCTAssertTrue([responseCache valueForKey:@"urlCache"] == dedicated, @"独占缓存注入失败");

    NSArray<NSURLRequest *> *requests = EMASUAFRequests(@"g1b");
    EMASUAFLog(@"G1b start: dedicated cache + EMASCurl only, iterations=%d", kEMASUAFIterations);
    EMASUAFLogCapacity(@"G1b dedicated", dedicated);

    dispatch_queue_t queue = dispatch_queue_create("uaf.g1b", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_async(group, queue, ^{
        EMASUAFEMASStoreLoop(responseCache, requests, kEMASUAFIterations);
    });
    dispatch_group_async(group, queue, ^{
        int hits = EMASUAFEMASLookupLoop(responseCache, requests, kEMASUAFIterations);
        EMASUAFLog(@"G1b reader hits=%d/%d", hits, kEMASUAFIterations);
    });

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    EMASUAFLog(@"G1b survived");
}

/// 第一组变体 c：sharedURLCache + 纯 EMASCurl，叠加与缓存完全无关的分配压力。
/// 外部线程只做对象分配/释放，绝不触碰任何 NSURLCache。
/// 用于区分「外部写缓存」究竟是逻辑必要条件，还是仅仅提高了命中概率的加压手段。
- (void)uafGroup1c_SharedCache_EMASCurlOnly_UnrelatedPressure {
    EMASCurlResponseCache *responseCache = [EMASCurlResponseCache new];
    NSArray<NSURLRequest *> *requests = EMASUAFRequests(@"g1c");

    EMASUAFLog(@"G1c start: sharedURLCache + EMASCurl only + unrelated alloc pressure(%d), iterations=%d",
               kEMASUAFExternalThreads, kEMASUAFIterations);

    dispatch_queue_t queue = dispatch_queue_create("uaf.g1c", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();
    __block atomic_bool stopPressure = false;

    dispatch_group_async(group, queue, ^{
        EMASUAFEMASStoreLoop(responseCache, requests, kEMASUAFIterations);
    });
    dispatch_group_async(group, queue, ^{
        int hits = EMASUAFEMASLookupLoop(responseCache, requests, kEMASUAFIterations);
        EMASUAFLog(@"G1c reader hits=%d/%d", hits, kEMASUAFIterations);
        atomic_store_explicit(&stopPressure, true, memory_order_relaxed);
    });

    // 与缓存无关的 16 字节 size class 分配churn，仅制造分配器与调度扰动
    for (int e = 0; e < kEMASUAFExternalThreads; e++) {
        dispatch_group_async(group, queue, ^{
            while (!atomic_load_explicit(&stopPressure, memory_order_relaxed)) {
                @autoreleasepool {
                    for (int i = 0; i < 2048; i++) {
                        EMASUAFFiller *filler = [EMASUAFFiller new];
                        [filler poison];
                        (void)filler;
                    }
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    EMASUAFLog(@"G1c survived");
}

/// 第二组（决定性）：sharedURLCache + 外部线程「只写」 + EMASCurl「只读」。
/// 外部线程扮演宿主 App 其他网络栈 / 第三方 SDK 对共享缓存的写入，
/// EMASCurl 侧不写，仅在自己的串行队列上 lookup。
///
/// 只有当崩溃线程为 com.alicloud.emascurl.cacheQueue 且栈顶为
/// _reestablishInternalCFCachedURLResponse: 时，才与客户现场完整一致；
/// 若崩溃落在外部写入线程，则本组不成立，需重新设计。
- (void)uafGroup2_SharedCache_ExternalWriteOnly_EMASCurlReadOnly {
    EMASCurlResponseCache *responseCache = [EMASCurlResponseCache new];
    NSURLCache *shared = [NSURLCache sharedURLCache];
    NSArray<NSURLRequest *> *requests = EMASUAFRequests(@"g2");

    EMASUAFLog(@"G2 start: external write-only(%d) + EMASCurl read-only, iterations=%d",
               kEMASUAFExternalThreads, kEMASUAFIterations);

    dispatch_queue_t queue = dispatch_queue_create("uaf.g2.external", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    // 外部：只写 sharedURLCache，不读
    for (int e = 0; e < kEMASUAFExternalThreads; e++) {
        dispatch_group_async(group, queue, ^{
            EMASUAFStoreLoop(shared, requests, kEMASUAFIterations);
        });
    }

    // EMASCurl：只读，经 com.alicloud.emascurl.cacheQueue
    dispatch_queue_t readerQueue = dispatch_queue_create("uaf.g2.emas", DISPATCH_QUEUE_CONCURRENT);
    for (int r = 0; r < 2; r++) {
        dispatch_group_async(group, readerQueue, ^{
            int hits = EMASUAFEMASLookupLoop(responseCache, requests, kEMASUAFIterations);
            EMASUAFLog(@"G2 SDK returned responses=%d/%d (not Foundation hits)", hits, kEMASUAFIterations);
            XCTAssertGreaterThan(hits, 0, @"夹具必须产生 SDK 可用响应，零返回不能作为有效命中对照");
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    EMASUAFLog(@"G2 survived");
}

/// 第二组对照：外部线程「只读」 + EMASCurl 读写。
/// 与第二组的唯一差异是外部访问方向。用于检验「外部写」是否为必要条件。
- (void)uafGroup2b_SharedCache_ExternalReadOnly {
    EMASCurlResponseCache *responseCache = [EMASCurlResponseCache new];
    NSURLCache *shared = [NSURLCache sharedURLCache];
    NSArray<NSURLRequest *> *requests = EMASUAFRequests(@"g2b");

    EMASUAFLog(@"G2b start: external read-only(%d) + EMASCurl read/write, iterations=%d",
               kEMASUAFExternalThreads, kEMASUAFIterations);

    dispatch_queue_t queue = dispatch_queue_create("uaf.g2b", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_async(group, queue, ^{
        EMASUAFEMASStoreLoop(responseCache, requests, kEMASUAFIterations);
    });
    dispatch_group_async(group, queue, ^{
        int hits = EMASUAFEMASLookupLoop(responseCache, requests, kEMASUAFIterations);
        EMASUAFLog(@"G2b emas reader hits=%d/%d", hits, kEMASUAFIterations);
    });

    for (int e = 0; e < kEMASUAFExternalThreads; e++) {
        dispatch_group_async(group, queue, ^{
            EMASUAFLookupLoop(shared, requests, kEMASUAFIterations);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    EMASUAFLog(@"G2b survived");
}

/// 第三组：EMASCurl 使用独占 NSURLCache（独立目录），外部线程持续写 sharedURLCache。
/// 这是独占缓存候选方案的实验，不是本版最终方案；它与 G2 的 SDK 读写线程模型也不同。
/// 通过 KVC 注入 SDK 自身属性 urlCache；不能将两组结果称为唯一变量对照。
- (void)uafGroup3_DedicatedCache_ExternalWritesShared {
    EMASCurlResponseCache *responseCache = [EMASCurlResponseCache new];
    NSURLCache *dedicated = EMASUAFDedicatedCache();
    [responseCache setValue:dedicated forKey:@"urlCache"];

    // 确认注入生效，否则本组结论无意义
    NSURLCache *injected = [responseCache valueForKey:@"urlCache"];
    XCTAssertTrue(injected == dedicated, @"独占缓存注入失败，本组结论不成立");
    XCTAssertTrue(injected != [NSURLCache sharedURLCache], @"注入后仍指向 sharedURLCache");
    EMASUAFLog(@"G3 injected dedicated cache=%p shared=%p",
               (__bridge void *)injected, (__bridge void *)[NSURLCache sharedURLCache]);
    EMASUAFLogCapacity(@"G3 dedicated", dedicated);
    EMASUAFLogCapacity(@"G3 shared", [NSURLCache sharedURLCache]);

    NSURLCache *shared = [NSURLCache sharedURLCache];
    NSArray<NSURLRequest *> *requests = EMASUAFRequests(@"g3");

    EMASUAFLog(@"G3 start: EMASCurl dedicated cache + external write shared(%d), iterations=%d",
               kEMASUAFExternalThreads, kEMASUAFIterations);

    dispatch_queue_t queue = dispatch_queue_create("uaf.g3", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    // EMASCurl 在独占实例上读写
    dispatch_group_async(group, queue, ^{
        EMASUAFEMASStoreLoop(responseCache, requests, kEMASUAFIterations);
    });
    dispatch_group_async(group, queue, ^{
        int hits = EMASUAFEMASLookupLoop(responseCache, requests, kEMASUAFIterations);
        EMASUAFLog(@"G3 reader hits=%d/%d", hits, kEMASUAFIterations);
    });

    // 外部持续写 sharedURLCache，压力强度与第二组一致
    for (int e = 0; e < kEMASUAFExternalThreads; e++) {
        dispatch_group_async(group, queue, ^{
            EMASUAFStoreLoop(shared, requests, kEMASUAFIterations);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    EMASUAFLog(@"G3 survived");
}

/// 第四组：完全不涉及 EMASCurl，纯 Foundation 对 sharedURLCache 并发读写。
/// 用于界定问题层级——若此组崩溃，说明该生命周期竞态位于 CFNetwork 缓存实现内，
/// 与 EMASCurl 的代码无关；EMASCurl 的缺陷在于「选用了共享实例」而非「写法错误」。
- (void)uafGroup4_SharedCache_FoundationOnly {
    NSURLCache *shared = [NSURLCache sharedURLCache];
    NSArray<NSURLRequest *> *requests = EMASUAFRequests(@"g4");

    EMASUAFLog(@"G4 start: Foundation only, writers=4 readers=4, iterations=%d", kEMASUAFIterations);

    dispatch_queue_t queue = dispatch_queue_create("uaf.g4", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    for (int w = 0; w < 4; w++) {
        dispatch_group_async(group, queue, ^{
            EMASUAFStoreLoop(shared, requests, kEMASUAFIterations);
        });
    }
    for (int r = 0; r < 4; r++) {
        dispatch_group_async(group, queue, ^{
            int hits = EMASUAFLookupLoop(shared, requests, kEMASUAFIterations);
            EMASUAFLog(@"G4 reader hits=%d/%d", hits, kEMASUAFIterations);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    EMASUAFLog(@"G4 survived");
}

/// 第五组：与第四组结构完全相同，唯一差异是 store 后将 wrapper 放入强引用池，
/// 使其不在缓存条目存活期间进入 dealloc。
/// 这是「延长 wrapper 生命周期」修复方向的直接验证：
/// 若本组稳定不崩而第四组崩，则该方向有效。
- (void)uafGroup5_SharedCache_RetainedWrappers {
    NSURLCache *shared = [NSURLCache sharedURLCache];
    NSArray<NSURLRequest *> *requests = EMASUAFRequests(@"g5");
    NSData *body = EMASUAFBody();

    EMASUAFLog(@"G5 start: retained wrappers, writers=4 readers=4, iterations=%d", kEMASUAFIterations);

    // 强引用池：保留最近 kPool 个 wrapper，避免 store 后立即 dealloc
    const int kPool = 8192;
    NSMutableArray *pool = [NSMutableArray arrayWithCapacity:kPool];
    dispatch_queue_t poolQueue = dispatch_queue_create("uaf.g5.pool", DISPATCH_QUEUE_SERIAL);

    dispatch_queue_t queue = dispatch_queue_create("uaf.g5", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    for (int w = 0; w < 4; w++) {
        dispatch_group_async(group, queue, ^{
            for (int n = 0; n < kEMASUAFIterations; n++) {
                @autoreleasepool {
                    NSURLRequest *request = [requests[n % requests.count] copy];
                    NSCachedURLResponse *wrapper =
                        [[NSCachedURLResponse alloc] initWithResponse:EMASUAFResponse(request.URL, body.length)
                                                                data:body
                                                            userInfo:nil
                                                       storagePolicy:NSURLCacheStorageAllowed];
                    [shared storeCachedResponse:wrapper forRequest:request];
                    dispatch_sync(poolQueue, ^{
                        [pool addObject:wrapper];
                        if (pool.count > kPool) {
                            [pool removeObjectsInRange:NSMakeRange(0, pool.count - kPool)];
                        }
                    });
                }
            }
        });
    }
    for (int r = 0; r < 4; r++) {
        dispatch_group_async(group, queue, ^{
            int hits = EMASUAFLookupLoop(shared, requests, kEMASUAFIterations);
            EMASUAFLog(@"G5 reader hits=%d/%d", hits, kEMASUAFIterations);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    EMASUAFLog(@"G5 survived (pool=%lu)", (unsigned long)pool.count);
}

#pragma mark - B. 诊断组（仅观测量，不构成证明）
/// store 前后的引用计数与内部 CF 指针状态。
/// 说明：CFGetRetainCount 会被临时 autorelease 引用干扰，不能据此断定所有权归属。
- (void)uafDiagnoseStoreOwnership {
    NSURLCache *cache = [NSURLCache sharedURLCache];

    EMASUAFLog(@"instanceSize NSCachedURLResponse=%zu EMASUAFFiller=%zu",
               class_getInstanceSize([NSCachedURLResponse class]),
               class_getInstanceSize([EMASUAFFiller class]));

    NSURLRequest *request = EMASUAFRequest(@"ownership.jpg");
    NSData *body = EMASUAFBody();

    uintptr_t wrapperAddress = 0;
    @autoreleasepool {
        NSCachedURLResponse *wrapper =
            [[NSCachedURLResponse alloc] initWithResponse:EMASUAFResponse(request.URL, body.length)
                                                    data:body
                                                userInfo:nil
                                           storagePolicy:NSURLCacheStorageAllowed];
        wrapperAddress = (uintptr_t)wrapper;

        void *cfBefore = EMASUAFInternalCFResponse(wrapper);
        long retainBefore = CFGetRetainCount((CFTypeRef)wrapper);

        [cache storeCachedResponse:wrapper forRequest:request];

        void *cfAfter = EMASUAFInternalCFResponse(wrapper);
        long retainAfter = CFGetRetainCount((CFTypeRef)wrapper);

        EMASUAFLog(@"wrapper=%p retain before=%ld after=%ld", (void *)wrapperAddress, retainBefore, retainAfter);
        EMASUAFLog(@"_CFCachedURLResponse before=%p after=%p", cfBefore, cfAfter);
    }

    NSCachedURLResponse *got = [cache cachedResponseForRequest:request];
    EMASUAFLog(@"lookup got=%p stored=%p sameAddress=%d class=%@",
               (__bridge void *)got, (void *)wrapperAddress,
               (uintptr_t)got == wrapperAddress ? 1 : 0,
               NSStringFromClass([got class]));
}

/// store 并出 autoreleasepool 后，wrapper 是否真的被释放。
/// weak 归零只能说明「调用方释放后无强引用」，不能证明 CFNetwork 侧持有的是裸指针。
- (void)uafDiagnoseLifetimeAfterStore {
    NSURLCache *cache = [NSURLCache sharedURLCache];
    NSURLRequest *request = EMASUAFRequest(@"lifetime.jpg");
    NSData *body = EMASUAFBody();

    __weak NSCachedURLResponse *weakWrapper = nil;
    uintptr_t address = 0;
    @autoreleasepool {
        NSCachedURLResponse *wrapper =
            [[NSCachedURLResponse alloc] initWithResponse:EMASUAFResponse(request.URL, body.length)
                                                    data:body
                                                userInfo:nil
                                           storagePolicy:NSURLCacheStorageAllowed];
        weakWrapper = wrapper;
        address = (uintptr_t)wrapper;
        [cache storeCachedResponse:wrapper forRequest:request];
        EMASUAFLog(@"in pool: wrapper=%p retain=%ld", (void *)address,
                   CFGetRetainCount((CFTypeRef)wrapper));
    }

    EMASUAFLog(@"after drain: weak=%p released=%d addr=%p",
               (__bridge void *)weakWrapper, weakWrapper == nil ? 1 : 0, (void *)address);
}

/// 用子类身份判别 lookup 返回对象是否为 store 进去的原对象。
/// 结果为「否」时只能说明该次 lookup 走了重建路径，不能排除反向指针路径存在。
- (void)uafDiagnoseProbeIdentity {
    NSURLCache *cache = [NSURLCache sharedURLCache];
    NSURLRequest *request = EMASUAFRequest(@"probe.jpg");
    NSData *body = EMASUAFBody();

    uintptr_t probeAddress = 0;
    @autoreleasepool {
        EMASUAFProbe *probe =
            [[EMASUAFProbe alloc] initWithResponse:EMASUAFResponse(request.URL, body.length)
                                             data:body
                                         userInfo:nil
                                    storagePolicy:NSURLCacheStorageAllowed];
        probeAddress = (uintptr_t)probe;
        [cache storeCachedResponse:probe forRequest:request];
    }

    NSCachedURLResponse *got = [cache cachedResponseForRequest:request];
    EMASUAFLog(@"probe lookup got=%p class=%@ isProbe=%d sameAddress=%d",
               (__bridge void *)got, NSStringFromClass([got class]),
               [got isKindOfClass:[EMASUAFProbe class]] ? 1 : 0,
               (uintptr_t)got == probeAddress ? 1 : 0);
}

#pragma mark - C. 注入组（故障注入，不代表真实触发路径）

/// 主动向被释放内存写入 0xd001，用于演示「x8 = self->_internal，far = x8 + 0x28」
/// 这一指令/寄存器关系。本用例统计 filler 是否真的复用了 wrapper 地址：
/// 若复用次数为 0，则它连「内存被抢占」这一前提都未成立，不具备任何证明力。
- (void)uafFaultInjectionPoisonedSlot {
    NSURLCache *cache = [NSURLCache sharedURLCache];
    NSData *body = EMASUAFBody();
    const int rounds = 300;
    const int fillerCount = 512;
    int reuseHits = 0;

    for (int round = 0; round < rounds; round++) {
        NSURLRequest *request = EMASUAFRequest([NSString stringWithFormat:@"inject-%d.jpg", round]);

        uintptr_t wrapperAddress = 0;
        @autoreleasepool {
            NSCachedURLResponse *wrapper =
                [[NSCachedURLResponse alloc] initWithResponse:EMASUAFResponse(request.URL, body.length)
                                                        data:body
                                                    userInfo:nil
                                               storagePolicy:NSURLCacheStorageAllowed];
            wrapperAddress = (uintptr_t)wrapper;
            [cache storeCachedResponse:wrapper forRequest:request];
        }

        NSMutableArray *fillers = [NSMutableArray arrayWithCapacity:fillerCount];
        for (int i = 0; i < fillerCount; i++) {
            EMASUAFFiller *filler = [EMASUAFFiller new];
            [filler poison];
            if ((uintptr_t)filler == wrapperAddress) {
                reuseHits++;
            }
            [fillers addObject:filler];
        }

        NSCachedURLResponse *got = [cache cachedResponseForRequest:request];
        (void)got.data.length;

        [fillers removeAllObjects];
    }

    EMASUAFLog(@"fault injection finished: rounds=%d addressReuseHits=%d", rounds, reuseHits);
    if (reuseHits == 0) {
        EMASUAFLog(@"注意：filler 从未复用 wrapper 地址，本用例不构成任何证明");
    }
}

#pragma mark - D. 基准组（性能量化，不构成因果证明）

/// 量化「lookup 返回防御性副本」的增量开销。
/// 两种容量配置构成对照：
///   memory-resident —— 内存容量足以容纳全部条目，测副本的纯 O(1) 开销
///   disk-resident   —— 内存容量远小于数据总量，强制条目落盘，用于回答
///                      「构造副本时读取 .data getter 会不会即时把响应体读出来」
/// lookupOnly 阶段刻意不触碰 .data，以对应 EMASCurlProtocol.m:1151 的条件请求路径。
///
/// 测量方式：多轮短循环，每轮内三种模式的执行顺序轮换，按轮取中位数与最小值。
/// 首版用「每模式一大段连续循环」测出了 touch 快于 copy 这种自相矛盾结果，
/// 说明顺序漂移与噪声量级已与待测信号相当，故必须交错采样。
/// 注意：跑在模拟器上，磁盘是宿主机 SSD，磁盘相关开销相对真机 NAND 会被低估。
- (void)uafBenchmarkDefensiveCopyCost {
    const int kURLs = 64;
    const int kRounds = 25;
    const int kRoundOps = 2000;

    // 第三组是「同样落盘、但 body 小 25 倍」的对照：
    // 若 lookupOnly 随 body 大小同比下降，说明响应体在 cachedResponseForRequest:
    // 内部就已被读出，.data getter 并非惰性加载，防御性副本因此不引入新的 I/O。
    NSArray<NSDictionary *> *configs = @[
        @{@"name": @"memory-resident-100KB", @"memory": @(64 * 1024 * 1024), @"body": @(100 * 1024)},
        @{@"name": @"disk-resident-100KB",   @"memory": @(64 * 1024),        @"body": @(100 * 1024)},
        @{@"name": @"disk-resident-4KB",     @"memory": @(64 * 1024),        @"body": @(4 * 1024)},
    ];

    const EMASUAFBenchMode modes[3] = {
        EMASUAFBenchLookupOnly,
        EMASUAFBenchLookupCopy,
        EMASUAFBenchLookupCopyTouch,
    };

    for (NSDictionary *config in configs) {
        @autoreleasepool {
            NSUInteger bodyBytes = [config[@"body"] unsignedIntegerValue];
            NSMutableData *mutableBody = [NSMutableData dataWithLength:bodyBytes];
            memset(mutableBody.mutableBytes, 0xAB, bodyBytes);
            NSData *body = [mutableBody copy];

            NSURLCache *cache = EMASUAFCacheWithCapacity([config[@"memory"] unsignedIntegerValue],
                                                         256 * 1024 * 1024);
            NSArray<NSURLRequest *> *requests = EMASUAFRequestsWithCount(@"bench", kURLs);
            EMASUAFFillCache(cache, requests, body);

            // 预热：建立磁盘条目索引，排除首次访问的一次性成本
            EMASUAFBenchRun(cache, requests, kURLs * 8, EMASUAFBenchLookupOnly, NULL);

            NSMutableArray<NSNumber *> *samples[3] = {
                [NSMutableArray arrayWithCapacity:kRounds],
                [NSMutableArray arrayWithCapacity:kRounds],
                [NSMutableArray arrayWithCapacity:kRounds],
            };
            int totalHits = 0;

            for (int round = 0; round < kRounds; round++) {
                // 每轮轮换起始模式，使三种模式在测量窗口中的位置均匀分布
                for (int offset = 0; offset < 3; offset++) {
                    int index = (round + offset) % 3;
                    int hits = 0;
                    uint64_t elapsed = EMASUAFBenchRun(cache, requests, kRoundOps, modes[index], &hits);
                    [samples[index] addObject:@((double)elapsed / (double)kRoundOps)];
                    totalHits += hits;
                }
            }

            double onlyMed = EMASUAFMedian(samples[0]);
            double copyMed = EMASUAFMedian(samples[1]);
            double touchMed = EMASUAFMedian(samples[2]);

            EMASUAFLog(@"bench[%@] body=%luKB rounds=%d ops/round=%d hits=%d/%d",
                       config[@"name"], (unsigned long)(bodyBytes / 1024), kRounds, kRoundOps,
                       totalHits, kRounds * 3 * kRoundOps);
            EMASUAFLog(@"bench[%@] median  only=%.0fns copy=%.0fns touch=%.0fns "
                       @"copyDelta=%.0fns touchDelta=%.0fns",
                       config[@"name"], onlyMed, copyMed, touchMed,
                       copyMed - onlyMed, touchMed - copyMed);
            EMASUAFLog(@"bench[%@] min     only=%.0fns copy=%.0fns touch=%.0fns "
                       @"copyDelta=%.0fns touchDelta=%.0fns",
                       config[@"name"],
                       EMASUAFMin(samples[0]), EMASUAFMin(samples[1]), EMASUAFMin(samples[2]),
                       EMASUAFMin(samples[1]) - EMASUAFMin(samples[0]),
                       EMASUAFMin(samples[2]) - EMASUAFMin(samples[1]));

            XCTAssertEqual(totalHits, kRounds * 3 * kRoundOps,
                           @"%@ 存在未命中，各模式不可比", config[@"name"]);
        }
    }

    EMASUAFLog(@"bench survived");
}

@end
