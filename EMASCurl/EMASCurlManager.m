//
//  MultiCurlManager.m
//  EMASCurl
//
//  Created by xuyecan on 2024/12/9.
//

#import "EMASCurlManager.h"
#import "EMASCurlLogger.h"

@interface EMASCurlManager () {
    CURLM *_multiHandle;
    CURLSH *_shareHandle;
    NSThread *_networkThread;
    NSCondition *_condition;
    NSMutableDictionary<NSNumber *, void (^)(BOOL, NSError *)> *_completionMap;
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

        _completionMap = [NSMutableDictionary dictionary];

        _condition = [[NSCondition alloc] init];
        _networkThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkThreadEntry) object:nil];
        _networkThread.qualityOfService = NSQualityOfServiceUserInitiated;
        [_networkThread start];

        EMAS_LOG_INFO(@"EC-Manager", @"EMASCurlManager initialized successfully with network thread started");
    }
    return self;
}

- (void)enqueueNewEasyHandle:(CURL *)easyHandle completion:(void (^)(BOOL, NSError *))completion {
    NSNumber *easyKey = @((uintptr_t)easyHandle);

    [_condition lock];

    // 在锁保护下操作_completionMap
    _completionMap[easyKey] = completion;
    EMAS_LOG_DEBUG(@"EC-Manager", @"Enqueueing new easy handle (total pending: %lu)", (unsigned long)_completionMap.count);

    curl_easy_setopt(easyHandle, CURLOPT_SHARE, _shareHandle);
    CURLMcode result = curl_multi_add_handle(_multiHandle, easyHandle);

    if (result != CURLM_OK) {
        EMAS_LOG_ERROR(@"EC-Manager", @"Failed to add easy handle to multi handle: %s", curl_multi_strerror(result));
        [_completionMap removeObjectForKey:easyKey];
        [_condition unlock];

        if (completion) {
            NSError *error = [NSError errorWithDomain:@"EMASCurlManager"
                                               code:result
                                           userInfo:@{NSLocalizedDescriptionKey: @(curl_multi_strerror(result))}];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(NO, error);
            });
        }
        return;
    }

    curl_multi_wakeup(_multiHandle);

    EMAS_LOG_DEBUG(@"EC-Manager", @"Easy handle added to multi handle successfully");

    [_condition signal];
    [_condition unlock];
}

#pragma mark - Thread Entry and Main Loop

- (void)networkThreadEntry {
    EMAS_LOG_INFO(@"EC-Manager", @"Network thread started");

    @autoreleasepool {
        [_condition lock];

        while (YES) {
            if (_completionMap.count == 0) {
                EMAS_LOG_DEBUG(@"EC-Manager", @"No pending requests, waiting for new work");
                [_condition wait];
            }

            // 唤醒后应该有任务需要处理
            // 在执行期间保持锁定，以防止添加新句柄时发生竞争条件
            [self processCurlMessages];

            if (_completionMap.count > 0) {
                [_condition unlock];

                // 等待网络事件，超时时间为250ms
                int numfds = 0;
                CURLMcode result = curl_multi_wait(_multiHandle, NULL, 0, 250, &numfds);
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
            void (^completion)(BOOL, NSError *) = _completionMap[easyKey];

            [_completionMap removeObjectForKey:easyKey];

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
            EMAS_LOG_DEBUG(@"EC-Manager", @"Removed easy handle from multi handle (remaining: %lu)", (unsigned long)_completionMap.count);

            if (completion) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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
