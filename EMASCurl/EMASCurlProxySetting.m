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
static dispatch_block_t s_pendingUpdateBlock;
static const double kProxyUpdateDebounceIntervalSec = 0.8;

// 类初始化时完成一次性初始化与监听启动
+ (void)initialize {
    if (self != [EMASCurlProxySetting class]) {
        return;
    }

    s_proxyQueue = dispatch_queue_create("com.alicloud.emascurl.proxyQueue", DISPATCH_QUEUE_SERIAL);
    s_cachedProxySettings = nil;
    s_proxyNotifyToken = 0;
    s_pendingUpdateBlock = NULL;

    [self startProxyObservation];
    [self updateProxySettingsAsyncInQueue];
}

+ (void)setManualProxyServer:(NSString *)proxyServerURL {
    BOOL manualEnabled = (proxyServerURL != nil && proxyServerURL.length > 0);
    dispatch_sync(s_proxyQueue, ^{
        s_manualProxyEnabled = manualEnabled;
        if (manualEnabled) {
            s_cachedProxySettings = nil;
            // 主动取消未执行的去抖更新，避免在切到手动代理后仍触发系统代理更新
            if (s_pendingUpdateBlock != NULL) {
                dispatch_block_cancel(s_pendingUpdateBlock);
                s_pendingUpdateBlock = NULL;
            }
        }
    });

    if (manualEnabled) {
        [self stopProxyObservation];
        EMAS_LOG_INFO(@"EC-Proxy", @"Manual proxy enabled: %@", proxyServerURL);
    } else {
        [self startProxyObservation];
        [self updateProxySettingsAsyncInQueue];
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
    // IPv6字面量需要使用方括号包裹，避免与端口分隔符":"冲突
    if ([host containsString:@":"]) {
        if (![host hasPrefix:@"["] && ![host hasSuffix:@"]"]) {
            host = [NSString stringWithFormat:@"[%@]", host];
        }
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
                                                  // 蜂窝/网络切换可能在短时间触发多次；
                                                  // 使用可取消的 pending block 去抖：新事件到来时取消旧计划并重排队。
                                                  dispatch_async(s_proxyQueue, ^{
                                                      if (s_manualProxyEnabled) {
                                                          return;
                                                      }
                                                      // 取消上一轮未执行的更新
                                                      if (s_pendingUpdateBlock != NULL) {
                                                          dispatch_block_cancel(s_pendingUpdateBlock);
                                                          s_pendingUpdateBlock = NULL;
                                                      }
                                                      // 创建新的可取消任务并按延迟入队
                                                      dispatch_block_t block = dispatch_block_create(0, ^{
                                                          [EMASCurlProxySetting _updateProxySettingsLocked];
                                                      });
                                                      s_pendingUpdateBlock = block;
                                                      int64_t nanos = (int64_t)(kProxyUpdateDebounceIntervalSec * (double)NSEC_PER_SEC);
                                                      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, nanos), s_proxyQueue, block);
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
        // 取消未执行的 pending 更新，避免停止后仍触发
        dispatch_sync(s_proxyQueue, ^{
            if (s_pendingUpdateBlock != NULL) {
                dispatch_block_cancel(s_pendingUpdateBlock);
                s_pendingUpdateBlock = NULL;
            }
        });
    });
}

+ (void)updateProxySettingsAsyncInQueue {
    dispatch_async(s_proxyQueue, ^{
        [self _updateProxySettingsLocked];
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

@end
