//
//  MultiCurlManager.m
//  EMASCurl
//
//  Created by xuyecan on 2024/12/9.
//

#import "EMASCurlManager.h"
#import "EMASCurlLogger.h"
#import <pthread.h>

@interface EMASCurlRequest : NSObject

@property (nonatomic, assign) CURL *easy;
@property (nonatomic, copy) void (^ _Nullable completion)(BOOL, NSError *);

@end

@implementation EMASCurlRequest
@end

@interface EMASCurlManager () {
    CURLM *_multiHandle;
    CURLSH *_shareHandle;
    NSThread *_networkThread;
    NSCondition *_condition;
    NSMutableDictionary<NSNumber *, EMASCurlRequest *> *_requestsByHandle;
    NSMutableArray<EMASCurlRequest *> *_pendingAddQueue;
}

@end

@implementation EMASCurlManager

+ (instancetype)sharedInstance {
    static EMASCurlManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[EMASCurlManager alloc] initPrivate];
    });
    return manager;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        EMAS_LOG_INFO(@"EC-Manager", @"Initializing EMASCurlManager");

        curl_global_init(CURL_GLOBAL_ALL);

        _multiHandle = curl_multi_init();
        if (!_multiHandle) {
            EMAS_LOG_ERROR(@"EC-Manager", @"Failed to initialize curl multi handle");
            return nil;
        }

        // cookie手动管理，所以这里不共享
        // 如果有需求，需要做实例隔离，整个架构要重新设计
        _shareHandle = curl_share_init();
        if (!_shareHandle) {
            EMAS_LOG_ERROR(@"EC-Manager", @"Failed to initialize curl share handle");
            curl_multi_cleanup(_multiHandle);
            return nil;
        }

        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_SSL_SESSION);
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_CONNECT);

        EMAS_LOG_DEBUG(@"EC-Manager", @"Configured share handle for DNS, SSL sessions, and connections");

        _requestsByHandle = [NSMutableDictionary dictionary];
        _pendingAddQueue = [NSMutableArray array];

        _condition = [[NSCondition alloc] init];
        _networkThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkThreadEntry) object:nil];
        _networkThread.qualityOfService = NSQualityOfServiceUserInitiated;
        [_networkThread start];

        EMAS_LOG_INFO(@"EC-Manager", @"EMASCurlManager initialized successfully with network thread started");
    }
    return self;
}

- (void)enqueueNewEasyHandle:(CURL *)easyHandle completion:(void (^)(BOOL, NSError *))completion {
    curl_easy_setopt(easyHandle, CURLOPT_SHARE, _shareHandle);

    EMASCurlRequest *request = [[EMASCurlRequest alloc] init];
    request.easy = easyHandle;
    request.completion = completion;

    [_condition lock];
    [_pendingAddQueue addObject:request];
    EMAS_LOG_DEBUG(@"EC-Manager", @"Enqueueing new easy handle (pending queue: %lu)", (unsigned long)_pendingAddQueue.count);
    [_condition signal];
    [_condition unlock];

    curl_multi_wakeup(_multiHandle);
}

#pragma mark - Thread Entry and Main Loop

- (void)networkThreadEntry {
    EMAS_LOG_INFO(@"EC-Manager", @"Network thread started");

    @autoreleasepool {
        [_condition lock];

        while (YES) {
            if (_requestsByHandle.count == 0 && _pendingAddQueue.count == 0) {
                EMAS_LOG_DEBUG(@"EC-Manager", @"No pending requests, waiting for new work");
                // 为避免“高QoS线程等待低QoS线程”导致的优先级反转告警，这里在进入阻塞等待前临时降低QoS；
                // 被唤醒后立刻恢复到较高QoS以尽快处理请求。
                pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
                [_condition wait];
                pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
            }

            [self drainPendingAddQueueLocked];

            [self processCurlMessages];

            if (_requestsByHandle.count > 0) {
                [_condition unlock];

                // 等待网络事件，超时时间为250ms
                int numfds = 0;
                CURLMcode result = curl_multi_poll(_multiHandle, NULL, 0, 250, &numfds);
                if (result != CURLM_OK) {
                    EMAS_LOG_ERROR(@"EC-Manager", @"curl_multi_wait failed: %s", curl_multi_strerror(result));
                }

                [_condition lock];
            }
        }
        // 因为全局都复用同一个manager，不会释放，因此理论上不会退出while循环
        // [_condition unlock];
    }

    EMAS_LOG_INFO(@"EC-Manager", @"Network thread stopped");
}

- (void)drainPendingAddQueueLocked {
    while (_pendingAddQueue.count > 0) {
        EMASCurlRequest *request = _pendingAddQueue.firstObject;
        [_pendingAddQueue removeObjectAtIndex:0];

        CURLMcode addResult = curl_multi_add_handle(_multiHandle, request.easy);
        if (addResult != CURLM_OK) {
            EMAS_LOG_ERROR(@"EC-Manager", @"Failed to add easy handle: %s", curl_multi_strerror(addResult));

            NSError *error = [NSError errorWithDomain:@"EMASCurlManager"
                                                 code:addResult
                                             userInfo:@{NSLocalizedDescriptionKey: @(curl_multi_strerror(addResult))}];

            curl_easy_cleanup(request.easy);

            void (^completion)(BOOL, NSError *) = request.completion;
            if (completion) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                    completion(NO, error);
                });
            }
            continue;
        }

        NSNumber *easyKey = @((uintptr_t)request.easy);
        _requestsByHandle[easyKey] = request;
        EMAS_LOG_DEBUG(@"EC-Manager", @"Easy handle added to multi handle successfully (total running: %lu)", (unsigned long)_requestsByHandle.count);
    }
}

- (void)processCurlMessages {
    int stillRunning = 0;
    CURLMsg *msg = NULL;
    int msgsLeft = 0;

    CURLMcode result = curl_multi_perform(_multiHandle, &stillRunning);
    if (result != CURLM_OK) {
        EMAS_LOG_ERROR(@"EC-Manager", @"curl_multi_perform failed: %s", curl_multi_strerror(result));
        return;
    }

    while ((msg = curl_multi_info_read(_multiHandle, &msgsLeft))) {
        if (msg->msg == CURLMSG_DONE) {
            CURL *easy = msg->easy_handle;
            NSNumber *easyKey = @((uintptr_t)easy);
            EMASCurlRequest *request = _requestsByHandle[easyKey];

            [_requestsByHandle removeObjectForKey:easyKey];

            BOOL succeeded = (msg->data.result == CURLE_OK);
            NSError *error = nil;

            // 获取请求的URL以便记录日志
            char *urlp = NULL;
            curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &urlp);
            NSString *url = urlp ? @(urlp) : @"unknown URL";

            // 获取响应状态码
            long responseCode = 0;
            curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &responseCode);

            if (succeeded) {
                EMAS_LOG_INFO(@"EC-Manager", @"Transfer completed successfully for URL: %@ (HTTP %ld)", url, responseCode);
            } else {
                EMAS_LOG_ERROR(@"EC-Manager", @"Transfer failed for URL: %@ - %s", url, curl_easy_strerror(msg->data.result));

                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: @(curl_easy_strerror(msg->data.result)),
                    NSURLErrorFailingURLStringErrorKey: url
                };
                error = [NSError errorWithDomain:@"EMASCurlManager" code:msg->data.result userInfo:userInfo];
            }

            curl_multi_remove_handle(_multiHandle, easy);
            // easy 句柄必须在从 multi 中移除后再 cleanup，避免并发销毁
            curl_easy_cleanup(easy);
            EMAS_LOG_DEBUG(@"EC-Manager", @"Removed easy handle from multi handle (remaining: %lu)", (unsigned long)_requestsByHandle.count);

            void (^completion)(BOOL, NSError *) = request.completion;
            if (completion) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                    completion(succeeded, error);
                });
            }
        }
    }
}

- (void)wakeup {
    // 唤醒等待，促使尽快进入 perform/回调。无需持锁即可安全调用。
    if (_multiHandle) {
        curl_multi_wakeup(_multiHandle);
    }
    // 同时signal条件量，确保线程从 wait 中返回
    [_condition lock];
    [_condition signal];
    [_condition unlock];
}

@end
