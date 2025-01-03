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
    NSMutableSet *_activeSockets;
}

typedef struct {
    __unsafe_unretained EMASCurlManager *manager;
    CURL *easy;
} CallbackContext;

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
        curl_multi_setopt(_multiHandle, CURLMOPT_SOCKETDATA, (__bridge void *)self);

        // 考虑客户端场景，在同一个App内共享cookie、dns、tcp连接是合理的
        // 如果有需求，需要做实例隔离，整个架构要重新设计
        _shareHandle = curl_share_init();
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_SSL_SESSION);
        curl_share_setopt(_shareHandle, CURLSHOPT_SHARE, CURL_LOCK_DATA_CONNECT);

        _completionMap = [NSMutableDictionary dictionary];
        _activeSockets = [NSMutableSet set];

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
    curl_multi_add_handle(_multiHandle, easyHandle);
    curl_easy_setopt(easyHandle, CURLOPT_SHARE, _shareHandle);
    [_condition signal];
    [_condition unlock];
}

- (void)networkThreadEntry {
    @autoreleasepool {
        [_condition lock];
        while (!_shouldStop) {
            [_condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            [self performCurlActions];
        }
        [_condition unlock];
    }
}

- (void)performCurlActions {
    int runningHandles = 0;
    curl_multi_perform(_multiHandle, &runningHandles);

    int msgsLeft = 0;
    CURLMsg *msg = NULL;
    while ((msg = curl_multi_info_read(_multiHandle, &msgsLeft))) {
        if (msg->msg == CURLMSG_DONE) {
            CURL *easy = msg->easy_handle;
            NSNumber *easyKey = @((uintptr_t)easy);

            void (^completion)(BOOL, NSError *) = _completionMap[easyKey];

            [_completionMap removeObjectForKey:easyKey];

            BOOL succeed = YES;
            NSError *error = nil;
            if (msg->data.result != CURLE_OK) {
                succeed = NO;

                char *urlp = NULL;
                curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &urlp);
                NSString *url = urlp ? @(urlp) : @"unknownURL";
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: @(curl_easy_strerror(msg->data.result)),
                    NSURLErrorFailingURLStringErrorKey: url
                };

                error = [NSError errorWithDomain:@"MultiCurlManager" code:msg->data.result userInfo:userInfo];
            }

            curl_multi_remove_handle(_multiHandle, easy);

            if (completion) {
                completion(succeed, error);
            }
        }
    }
}

@end
