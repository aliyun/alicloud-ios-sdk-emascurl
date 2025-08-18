//
//  EMASLocalHttpProxy.h
//  iOS Local HTTP Proxy Solution
//
//  EMAS本地HTTP代理服务接口定义
//  支持多种客户端类型：WKWebView、NSURLSession等
//  提供透明代理支持，集成自定义DNS解析服务
//
//  主要功能：
//  • 自动启动本地HTTP代理服务（支持iOS 12.0+）
//  • 支持HTTPS CONNECT协议代理
//  • 无缝集成自定义DNS解析服务（如HTTPDNS）
//  • WKWebView代理配置支持（需要iOS 17.0+）
//  • NSURLSession代理配置支持（支持iOS 12.0+）
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
 *  - NSURLSession：支持iOS 12.0+，通过connectionProxyDictionary配置
 *  - WKWebView：需要iOS 17.0+，通过WKWebsiteDataStore配置
 *
 *  使用场景：
 *  - 移动应用网络请求代理
 *  - 自定义DNS解析服务集成（如HTTPDNS）
 *  - 网络访问监控和分析
 *  - 网络请求调试和优化
 */
API_AVAILABLE(ios(12.0))
@interface EMASLocalHttpProxy : NSObject

#pragma mark - 核心服务管理

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
+ (BOOL)isProxyReady API_AVAILABLE(ios(12.0));

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
+ (void)setLogLevel:(EMASLocalHttpProxyLogLevel)logLevel API_AVAILABLE(ios(12.0));

/**
 *  设置自定义DNS解析器
 *
 *  通过此方法可注入自定义DNS解析逻辑，实现与具体DNS服务的解耦
 *  支持各种DNS服务，如阿里云HTTPDNS、腾讯云HTTPDNS、自建DNS等
 *
 *
 *  @code
 *  // 示例：集成阿里云HTTPDNS
 *  [EMASLocalHttpProxy setDNSResolverBlock:^NSArray<NSString *> *(NSString *hostname) {
 *      NSString *ip = [[HttpDnsService sharedInstance] getIpByHostSync:hostname];
 *      return ip ? @[ip] : nil;
 *  }];
 *
 *  // 示例：集成自定义DNS解析
 *  [EMASLocalHttpProxy setDNSResolverBlock:^NSArray<NSString *> *(NSString *hostname) {
 *      NSArray *ips = [MyCustomDNSResolver resolveHostToMultipleIPs:hostname];
 *      return ips;
 *  }];
 *  @endcode
 */
+ (void)setDNSResolverBlock:(NSArray<NSString *> * _Nullable (^)(NSString *hostname))resolverBlock API_AVAILABLE(ios(12.0));

#pragma mark - NSURLSession集成

/**
 *  配置NSURLSessionConfiguration使用本地代理
 *
 *  将本地代理服务集成到NSURLSession网络请求中，支持HTTPS请求通过代理转发
 *  支持iOS 12.0+，基于Network.framework实现，是推荐的集成方式
 *
 *  执行流程：
 *  1. 检查代理服务运行状态
 *  2. 获取当前代理端口信息
 *  3. 配置URLSession代理字典
 *  4. 应用HTTPS代理配置
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
+ (BOOL)installIntoUrlSessionConfiguration:(NSURLSessionConfiguration *)configuration API_AVAILABLE(ios(12.0));


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
+ (BOOL)installIntoWebViewConfiguration:(WKWebViewConfiguration *)configuration API_AVAILABLE(ios(17.0));


@end

NS_ASSUME_NONNULL_END
