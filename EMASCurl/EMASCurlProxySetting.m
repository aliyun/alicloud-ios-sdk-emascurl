//
//  EMASCurlProxySetting.m
//  EMASCurl
//
//  Created by Claude Code on 2025/10/30.
//

#import "EMASCurlProxySetting.h"
#import "EMASCurlLogger.h"
#import <CFNetwork/CFNetwork.h>
#import <notify.h>

@implementation EMASCurlProxySetting

// 仅负责代理逻辑的线程安全与系统通知监听
static dispatch_queue_t s_proxyQueue;
static NSDictionary *s_cachedProxySettings;
static BOOL s_manualProxyEnabled;
static int s_proxyNotifyToken;
static dispatch_source_t s_proxyDebounceTimer;

// 类初始化时完成一次性初始化与监听启动
+ (void)initialize {
    if (self != [EMASCurlProxySetting class]) {
        return;
    }

    s_proxyQueue = dispatch_queue_create("com.alicloud.emascurl.proxyQueue", DISPATCH_QUEUE_SERIAL);
    s_cachedProxySettings = nil;
    s_proxyNotifyToken = 0;
    s_proxyDebounceTimer = NULL;

    [self startProxyObservation];
    [self updateProxySettings];
}

+ (void)setManualProxyServer:(NSString *)proxyServerURL {
    BOOL manualEnabled = (proxyServerURL != nil && proxyServerURL.length > 0);
    dispatch_sync(s_proxyQueue, ^{
        s_manualProxyEnabled = manualEnabled;
        if (manualEnabled) {
            s_cachedProxySettings = nil;
        }
    });

    if (manualEnabled) {
        [self stopProxyObservation];
        EMAS_LOG_INFO(@"EC-Proxy", @"Manual proxy enabled: %@", proxyServerURL);
    } else {
        [self startProxyObservation];
        [self updateProxySettings];
        EMAS_LOG_INFO(@"EC-Proxy", @"Manual proxy disabled, will use system settings");
    }
}

+ (nullable NSString *)proxyServerForURL:(NSURL *)url {
    if (!url) {
        return nil;
    }

    __block NSDictionary *proxySettings = nil;
    dispatch_sync(s_proxyQueue, ^{
        proxySettings = s_cachedProxySettings;
    });
    if (!proxySettings) {
        return nil;
    }

    CFArrayRef proxiesRef = CFNetworkCopyProxiesForURL((__bridge CFURLRef)url, (__bridge CFDictionaryRef)proxySettings);
    if (!proxiesRef) {
        return nil;
    }

    NSArray *proxies = CFBridgingRelease(proxiesRef);
    NSDictionary *proxyInfo = nil;
    for (NSDictionary *candidate in proxies) {
        NSString *candidateType = candidate[(NSString *)kCFProxyTypeKey];
        if ([candidateType isEqualToString:(NSString *)kCFProxyTypeNone]) {
            continue;
        }
        if ([candidateType isEqualToString:(NSString *)kCFProxyTypeHTTP] ||
            [candidateType isEqualToString:(NSString *)kCFProxyTypeHTTPS] ||
            [candidateType isEqualToString:(NSString *)kCFProxyTypeSOCKS]) {
            proxyInfo = candidate;
            break;
        }
    }
    if (!proxyInfo) {
        return nil;
    }

    NSString *type = proxyInfo[(NSString *)kCFProxyTypeKey];
    NSString *host = proxyInfo[(NSString *)kCFProxyHostNameKey];
    NSNumber *port = proxyInfo[(NSString *)kCFProxyPortNumberKey];
    if (host.length == 0 || port == nil) {
        return nil;
    }

    // 非显式支持的类型不返回
    NSString *scheme = @"http";
    if ([type isEqualToString:(NSString *)kCFProxyTypeHTTPS]) {
        scheme = @"https";
    } else if ([type isEqualToString:(NSString *)kCFProxyTypeSOCKS]) {
        scheme = @"socks5";
    } else if (![type isEqualToString:(NSString *)kCFProxyTypeHTTP]) {
        return nil;
    }

    return [NSString stringWithFormat:@"%@://%@:%@", scheme, host, port];
}

#pragma mark - Internal

// 使用 Darwin 通知监听系统网络配置变化，避免轮询
+ (void)startProxyObservation {
    dispatch_async(dispatch_get_main_queue(), ^{
        __block BOOL manualEnabled = NO;
        __block int existingToken = 0;
        dispatch_sync(s_proxyQueue, ^{
            manualEnabled = s_manualProxyEnabled;
            existingToken = s_proxyNotifyToken;
        });
        if (manualEnabled) {
            return;
        }
        if (existingToken != 0) {
            return;
        }

        int token = 0;
        int status = notify_register_dispatch("com.apple.system.config.network_change",
                                              &token,
                                              dispatch_get_main_queue(),
                                              ^(int notifyToken) {
                                                  (void)notifyToken;
                                                  // Darwin 通知在蜂窝切换时可能短时间内多次触发；
                                                  // 在内部串行队列上做一次性定时器去抖，合并为一次更新。
                                                  dispatch_async(s_proxyQueue, ^{
                                                      if (s_manualProxyEnabled) {
                                                          return;
                                                      }
                                                      if (s_proxyDebounceTimer == NULL) {
                                                          s_proxyDebounceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, s_proxyQueue);
                                                          dispatch_source_set_event_handler(s_proxyDebounceTimer, ^{
                                                              [EMASCurlProxySetting _updateProxySettingsLocked];
                                                          });
                                                          dispatch_resume(s_proxyDebounceTimer);
                                                      }
                                                      uint64_t delay = 800ull * 1000000ull; // 800ms
                                                      uint64_t leeway = 100ull * 1000000ull; // 100ms
                                                      dispatch_source_set_timer(s_proxyDebounceTimer,
                                                                                dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay),
                                                                                0,
                                                                                leeway);
                                                  });
                                              });
        if (status != NOTIFY_STATUS_OK) {
            dispatch_sync(s_proxyQueue, ^{
                s_proxyNotifyToken = 0;
            });
            return;
        }

        dispatch_sync(s_proxyQueue, ^{
            s_proxyNotifyToken = token;
        });
    });
}

+ (void)stopProxyObservation {
    dispatch_async(dispatch_get_main_queue(), ^{
        __block int token = 0;
        dispatch_sync(s_proxyQueue, ^{
            token = s_proxyNotifyToken;
            s_proxyNotifyToken = 0;
        });
        if (token != 0) {
            notify_cancel(token);
        }
        // 清理去抖定时器，避免悬挂触发
        dispatch_sync(s_proxyQueue, ^{
            if (s_proxyDebounceTimer != NULL) {
                dispatch_source_cancel(s_proxyDebounceTimer);
                s_proxyDebounceTimer = NULL;
            }
        });
    });
}

// 内部方法要求在 s_proxyQueue 上调用，避免回调与更新之间的互锁
+ (void)_updateProxySettingsLocked {
    if (s_manualProxyEnabled) {
        return;
    }

    EMAS_LOG_INFO(@"EC-Proxy", @"Try to update proxy config.");

    CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
    if (!proxySettings) {
        s_cachedProxySettings = nil;
        return;
    }

    NSDictionary *proxyDict = CFBridgingRelease(proxySettings);
    if (proxyDict.count == 0) {
        s_cachedProxySettings = nil;
        return;
    }

    s_cachedProxySettings = [proxyDict copy];
}

+ (void)updateProxySettings {
    dispatch_sync(s_proxyQueue, ^{
        [self _updateProxySettingsLocked];
    });
}

@end
