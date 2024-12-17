//
//  MultiCurlManager.m
//  EMASCurl
//
//  Created by xuyecan on 2024/12/9.
//

#import "EMASCurlManager.h"

@interface EMASCurlManager () {
    CURLM *_multiHandle;
    NSThread *_networkThread;
    NSCondition *_condition;
    BOOL _shouldStop;
    NSMutableDictionary<NSNumber *, void (^)(BOOL, NSError *)> *_completionMap;
    NSMutableSet *activeSockets;
}

typedef struct {
    __unsafe_unretained EMASCurlManager *manager;
    CURL *easy;
} CallbackContext;

// Internal callbacks
static size_t writeCallback(char *ptr, size_t size, size_t nmemb, void *userdata);
static int socketCallback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp);
static int timerCallback(CURLM *multi, long timeout_ms, void *userp);

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
        curl_multi_setopt(_multiHandle, CURLMOPT_SOCKETFUNCTION, socketCallback);
        curl_multi_setopt(_multiHandle, CURLMOPT_SOCKETDATA, (__bridge void *)self);
        curl_multi_setopt(_multiHandle, CURLMOPT_TIMERFUNCTION, timerCallback);
        curl_multi_setopt(_multiHandle, CURLMOPT_TIMERDATA, (__bridge void *)self);

        _completionMap = [NSMutableDictionary dictionary];

        _condition = [[NSCondition alloc] init];
        _shouldStop = NO;

        _networkThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkThreadEntry) object:nil];
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
    curl_global_cleanup();
}

- (void)stop {
    [_condition lock];
    _shouldStop = YES;
    [_condition signal];
    [_condition unlock];
}

- (void)enqueueNewEasyHanlde:(CURL *)easyHandle completion:(void (^)(BOOL, NSError *))completion {
    NSNumber *easyKey = @((uintptr_t)easyHandle);
    _completionMap[easyKey] = completion;

    [_condition lock];
    curl_multi_add_handle(_multiHandle, easyHandle);
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
                error = [NSError errorWithDomain:@"MultiCurlManager"
                                            code:msg->data.result
                                        userInfo:@{NSLocalizedDescriptionKey: @(curl_easy_strerror(msg->data.result))}];
            }

            curl_multi_remove_handle(_multiHandle, easy);

            if (completion) {
                completion(succeed, error);
            }
        }
    }
}

// MARK: - Callbacks
static int socketCallback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp) {
    EMASCurlManager *selfRef = (__bridge EMASCurlManager *)userp;
    NSMutableSet *activeSockets = selfRef->activeSockets;

    switch (what) {
        case CURL_POLL_IN:
        case CURL_POLL_OUT:
        case CURL_POLL_INOUT:
            [activeSockets addObject:@(s)];
            break;
        case CURL_POLL_REMOVE:
            [activeSockets removeObject:@(s)];
            break;
        default:
            break;
    }

    return 0;
}

static int timerCallback(CURLM *multi, long timeout_ms, void *userp) {
    // Set a timer or just rely on polling in our thread loop.
    return 0;
}

@end
