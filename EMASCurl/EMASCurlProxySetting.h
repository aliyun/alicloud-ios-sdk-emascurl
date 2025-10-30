//
//  EMASCurlProxySetting.h
//  EMASCurl
//
//  Created by Claude Code on 2025/10/30.
//

#import <Foundation/Foundation.h>

@interface EMASCurlProxySetting : NSObject

/// 设置手动代理串；非空且非空串视为启用手动代理
/// 仅影响系统代理监听与缓存，不持久化配置
+ (void)setManualProxyServer:(nullable NSString *)proxyServerURL;

/// 基于缓存的系统代理为目标 URL 计算代理串
/// 返回格式：scheme://host:port；无可用代理时返回 nil
+ (nullable NSString *)proxyServerForURL:(nullable NSURL *)url;

@end
