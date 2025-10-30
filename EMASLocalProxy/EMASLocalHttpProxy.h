//
//  EMASLocalHttpProxy.h
//  iOS Local HTTP Proxy Solution
//
//  EMAS本地HTTP代理服务接口定义
//  支持多种客户端类型：WKWebView、NSURLSession等
//  提供透明代理支持，集成自定义DNS解析服务
//
//  主要功能：
//  • 自动启动本地HTTP代理服务
//  • 无缝集成自定义DNS解析服务（如HTTPDNS）
//  • WKWebView代理配置支持（需要iOS 17.0+）
//  • NSURLSession代理配置支持（支持iOS 17.0+）
//
//  Created by Alibaba Cloud EMAS Team on 2025/06/28.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  本地HTTP代理服务日志级别
 */
typedef NS_ENUM(NSInteger, EMASLocalHttpProxyLogLevel) {
    EMASLocalHttpProxyLogLevelNone = 0,     ///< 禁用所有日志
    EMASLocalHttpProxyLogLevelError,        ///< 仅ERROR级别
    EMASLocalHttpProxyLogLevelInfo,         ///< ERROR + INFO级别
    EMASLocalHttpProxyLogLevelDebug         ///< 所有日志级别（包括DEBUG）
};

/**
 *  自定义日志处理器 Block 类型
 *
 *  @param level 日志级别
 *  @param component 组件名称（如 "DNS", "Connection", "Proxy"）
 *  @param message 日志消息内容
 */
typedef void(^EMASLocalHttpProxyLogHandlerBlock)(EMASLocalHttpProxyLogLevel level, NSString * _Nonnull component, NSString * _Nonnull message);

/**
 *  EMAS本地HTTP代理服务
 *
 *  静态工具类，提供统一的API接口用于各种网络客户端的代理配置
 *  支持集成自定义DNS解析服务，实现域名解析优化和网络访问监控
 *
 *  核心特性：
 *  - 静态API设计：无需管理实例，直接调用类方法
 *  - 自动生命周期管理：类加载时自动启动代理服务
 *  - 高性能转发：基于Network framework的异步I/O
 *  - 安全隔离：仅监听本地回环地址，避免安全风险
 *  - 多客户端支持：同时支持NSURLSession和WKWebView
 *
 *  支持的网络客户端：
 *  - NSURLSession：支持iOS 17.0+，通过proxyConfigurations API配置
 *  - WKWebView：需要iOS 17.0+，通过WKWebsiteDataStore配置
 *
 *  使用场景：
 *  - 移动应用网络请求代理
 *  - 自定义DNS解析服务集成（如HTTPDNS）
 *  - 网络访问监控和分析
 *  - 网络请求调试和优化
 */
@interface EMASLocalHttpProxy : NSObject

#pragma mark - 核心服务管理

/**
 *  获取当前代理服务监听端口
 *
 *  返回本地代理服务当前使用的端口号，可用于调试和监控
 *  如果代理服务未启动，返回0
 *
 *  @return 代理服务端口号，0表示服务未启动
 *
 *  @note 此方法是线程安全的，可以从任意线程调用
 *  @note 端口号在代理服务启动时自动分配，范围为31000-32000
 *
 *  @code
 *  // 获取当前代理端口
 *  uint16_t port = [EMASLocalHttpProxy proxyPort];
 *  if (port > 0) {
 *      NSLog(@"代理服务运行在端口: %d", port);
 *  } else {
 *      NSLog(@"代理服务未启动");
 *  }
 *  @endcode
 */
+ (uint16_t)proxyPort;

/**
 *  检查代理服务是否已就绪
 *
 *  此方法提供线程安全的代理服务状态检查，可用于判断是否可以安全地配置网络客户端使用代理
 *  代理服务在类加载时自动启动，但启动过程是异步的，可能需要一定时间
 *
 *  @return YES表示代理服务已就绪可用，NO表示服务未启动或启动失败
 *
 *  @note 此方法是线程安全的，可以从任意线程调用
 *  @note 即使返回YES，后续的代理配置仍可能因网络环境等因素失败，建议检查配置方法的返回值
 *
 *  @code
 *  // 检查代理状态
 *  if ([EMASLocalHttpProxy isProxyReady]) {
 *      // 代理服务可用，可以安全配置
 *      [EMASLocalHttpProxy installIntoUrlSessionConfiguration:config];
 *  } else {
 *      // 代理服务不可用，使用系统网络
 *      NSLog(@"代理服务未就绪，将使用系统默认网络");
 *  }
 *  @endcode
 */
+ (BOOL)isProxyReady;

/**
 *  设置代理服务日志级别
 *
 *  通过此方法可控制代理服务的日志输出级别，用于调试和生产环境的日志管理
 *
 *
 *  @code
 *  // 开发环境：启用详细日志
 *  [EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelDebug];
 *
 *  // 生产环境：仅显示重要信息
 *  [EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelError];
 *  @endcode
 */
+ (void)setLogLevel:(EMASLocalHttpProxyLogLevel)logLevel;

/**
 *  设置自定义日志处理器
 *
 *  允许用户自定义日志输出目标，例如写入文件、发送到远程服务或显示在UI
 *  如果不设置自定义处理器，日志默认输出到控制台（NSLog）
 *
 *  @param handler 自定义日志处理器，传入 nil 恢复默认 NSLog 行为
 *
 *  @note 此方法是线程安全的
 *  @note handler 会在日志产生的线程上调用，如需UI操作请切换到主线程
 *
 *  @code
 *  // 示例：将日志写入文件
 *  [EMASLocalHttpProxy setLogHandler:^(EMASLocalHttpProxyLogLevel level, NSString *component, NSString *message) {
 *      [MyLogger writeToFile:message level:level component:component];
 *  }];
 *
 *  // 恢复默认NSLog行为
 *  [EMASLocalHttpProxy setLogHandler:nil];
 *  @endcode
 */
+ (void)setLogHandler:(nullable EMASLocalHttpProxyLogHandlerBlock)handler;

/**
 *  设置自定义DNS解析器
 *
 *  通过此方法可注入自定义DNS解析逻辑，实现与具体DNS服务的解耦
 *
 *  @code
 *  // 示例：集成阿里云HTTPDNS
 *  [EMASLocalHttpProxy setDNSResolverBlock:^NSArray<NSString *> * _Nullable(NSString * _Nonnull hostname) {
 *      HttpDnsService *httpdns = [HttpDnsService sharedInstance];
 *      HttpdnsResult *result = [httpdns resolveHostSyncNonBlocking:hostname byIpType:HttpdnsQueryIPTypeBoth];
 *
 *      if (result && (result.hasIpv4Address || result.hasIpv6Address)) {
 *          NSMutableArray<NSString *> *allIPs = [NSMutableArray array];
 *          if (result.hasIpv4Address) {
 *              [allIPs addObjectsFromArray:result.ips];
 *          }
 *          if (result.hasIpv6Address) {
 *              [allIPs addObjectsFromArray:result.ipv6s];
 *          }
 *          NSLog(@"HTTPDNS解析成功，域名: %@, IP: %@", hostname, allIPs);
 *          return allIPs;
 *      }
 *
 *      NSLog(@"HTTPDNS解析失败，域名: %@", hostname);
 *      return nil;
 *  }];
 *
 *  @endcode
 */
+ (void)setDNSResolverBlock:(NSArray<NSString *> * _Nullable (^)(NSString *hostname))resolverBlock;

#pragma mark - NSURLSession集成

/**
 *  配置NSURLSessionConfiguration使用本地代理
 *
 *  将本地代理服务集成到NSURLSession网络请求中，支持HTTPS请求通过代理转发
 *  支持iOS 10.0+，iOS 17.0+优先使用proxyConfigurations API，低版本使用connectionProxyDictionary
 *
 *  执行流程：
 *  1. 检查代理服务运行状态
 *  2. 获取当前代理端口信息
 *  3. iOS 17.0+: 创建nw_proxy_config_t并使用proxyConfigurations API
 *  4. iOS 10.0-16.x: 使用connectionProxyDictionary配置代理字典
 *
 *  @return YES表示代理配置成功，NO表示使用系统网络
 *
 *  @code
 *  // 使用示例
 *  NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
 *  BOOL success = [EMASLocalHttpProxy installIntoUrlSessionConfiguration:config];
 *  NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
 *  @endcode
 */
+ (BOOL)installIntoUrlSessionConfiguration:(NSURLSessionConfiguration *)configuration;


#pragma mark - WKWebView集成（iOS 17.0+）

/**
 *  配置WKWebViewConfiguration使用本地代理
 *
 *  WKWebView代理配置接口，支持iOS 17.0+系统
 *  代理服务已在类加载时自动启动，此方法专注于WebView配置
 *
 *  执行流程：
 *  1. 系统版本检查：iOS 17.0+支持代理配置
 *  2. 检查代理服务状态
 *  3. 创建本地代理端点配置
 *  4. 应用代理配置到WebView数据存储
 *
 *  @return YES表示代理配置成功，NO表示使用系统网络
 *
 *  @code
 *  // 简单使用示例
 *  WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
 *  BOOL success = [EMASLocalHttpProxy installIntoWebViewConfiguration:config];
 *  WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
 *  @endcode
 *
 *  @warning 此方法需要iOS 17.0+，在较低版本系统上会返回NO
 */
+ (BOOL)installIntoWebViewConfiguration:(WKWebViewConfiguration *)configuration;


@end

NS_ASSUME_NONNULL_END
