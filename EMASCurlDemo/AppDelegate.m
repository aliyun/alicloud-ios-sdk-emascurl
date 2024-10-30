//
//  AppDelegate.m
//  EMASNetDemo
//
//  Created by xin yu on 2024/9/23.
//

#import "AppDelegate.h"
#import <AlicloudHttpDNS/AlicloudHttpDNS.h>

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.

    // 使用阿里云HTTPDN控制台分配的AccountId构造全局实例
    // 全局只需要初始化一次
    HttpDnsService *httpdns = [[HttpDnsService alloc] initWithAccountID:129634];

    // 若开启了鉴权访问，则需要到控制台获得鉴权密钥并在初始化时进行配置
    // HttpDnsService *httpdns = [[HttpDnsService alloc] initWithAccountID:xxxxxx secretKey:@"your secret key"];

    // 打开日志，调试排查问题时使用
    [httpdns setLogEnabled:NO];

    // 设置httpdns域名解析网络请求是否需要走HTTPS方式
    [httpdns setHTTPSRequestEnabled:YES];

    // 设置开启持久化缓存，使得APP启动后可以复用上次活跃时缓存在本地的IP，提高启动后获取域名解析结果的速度
    [httpdns setPersistentCacheIPEnabled:YES];

    // 设置允许使用已经过期的IP，当域名的IP配置比较稳定时可以使用，提高解析效率
    [httpdns setReuseExpiredIPEnabled:YES];

    // 设置底层HTTPDNS网络请求超时时间，单位为秒
    [httpdns setTimeoutInterval:2];

    // 设置是否支持IPv6地址解析，只有开启这个开关，解析接口才有能力解析域名的IPv6地址并返回
    [httpdns setIPv6Enabled:YES];

    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


@end
