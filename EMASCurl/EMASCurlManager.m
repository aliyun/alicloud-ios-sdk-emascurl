//
//  MultiCurlManager.m
//  EMASCurl
//
//  Created by xuyecan on 2024/12/9.
//

#import "EMASCurlManager.h"

@interface EMASCurlManager () {
    CURLM *_multiHandle;
    CURLSH *_shareHandle;
    NSThread *_networkThread;
    NSCondition *_condition;
    BOOL _shouldStop;
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
        curl_global_init(CURL_GLOBAL_ALL);

        _multiHandle = curl_multi_init();

        // cookie手动管理，所以这里不共享
        // 如果有需求，需要做实例隔离，整个架构要重新设计
        _shareHandle = curl_share_init();
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_SSL_SESSION);
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_CONNECT);

        _completionMap = [NSMutableDictionary dictionary];

        _condition = [[NSCondition alloc] init];
        _shouldStop = NO;
        _networkThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkThreadEntry) object:nil];
        _networkThread.qualityOfService = NSQualityOfServiceUserInitiated;
        [_networkThread start];
    }
    return self;
}

- (void)dealloc {
    [self stop];
    if (_multiHandle) {
        curl_multi_cleanup(_multiHandle);
        _multiHandle = NULL;
    }
    if (_shareHandle) {
        curl_share_cleanup(_shareHandle);
        _shareHandle = NULL;
    }
    curl_global_cleanup();
}

- (void)stop {
    [_condition lock];
    _shouldStop = YES;
    [_condition signal];
    [_condition unlock];
}

- (void)enqueueNewEasyHandle:(CURL *)easyHandle completion:(void (^)(BOOL, NSError *))completion {
    NSNumber *easyKey = @((uintptr_t)easyHandle);
    _completionMap[easyKey] = completion;

    [_condition lock];

    curl_easy_setopt(easyHandle, CURLOPT_SHARE, _shareHandle);
    curl_multi_add_handle(_multiHandle, easyHandle);

    [_condition signal];
    [_condition unlock];
}

#pragma mark - Thread Entry and Main Loop

- (void)networkThreadEntry {
    @autoreleasepool {
        [_condition lock];

        while (!_shouldStop) {
            if (_completionMap.count == 0) {
                [_condition wait];
                if (_shouldStop) {
                    break;
                }
            }

            [self performCurlTransfers];

            if (_completionMap.count > 0 && !_shouldStop) {
                [_condition unlock];

                curl_multi_wait(_multiHandle, NULL, 0, 1000, NULL);

                [_condition lock];
            }
        }
        [_condition unlock];
    }
}

- (void)performCurlTransfers {
    int stillRunning = 0;
    CURLMsg *msg = NULL;
    int msgsLeft = 0;

    do {
        curl_multi_perform(_multiHandle, &stillRunning);

        while ((msg = curl_multi_info_read(_multiHandle, &msgsLeft))) {
            if (msg->msg == CURLMSG_DONE) {
                CURL *easy = msg->easy_handle;
                NSNumber *easyKey = @((uintptr_t)easy);
                void (^completion)(BOOL, NSError *) = _completionMap[easyKey];

                [_completionMap removeObjectForKey:easyKey];

                BOOL succeeded = (msg->data.result == CURLE_OK);
                NSError *error = nil;
                if (!succeeded) {
                    char *urlp = NULL;
                    curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &urlp);
                    NSString *url = urlp ? @(urlp) : @"unknownURL";
                    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @(curl_easy_strerror(msg->data.result)), NSURLErrorFailingURLStringErrorKey: url };
                    error = [NSError errorWithDomain:@"MultiCurlManager" code:msg->data.result userInfo:userInfo];
                }

                curl_multi_remove_handle(_multiHandle, easy);

                if (completion) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        completion(succeeded, error);
                    });
                }
            }
        }
    } while (stillRunning > 0);
}

@end
