//
//  ViewController.m
//  EMASCurlDemo
//
//  Created by xin yu on 2024/9/23.
//

#import "ViewController.h"
#import "RequestDemoController.h"
#import "Http3DemoController.h"
#import "WkWebViewDemoController.h"
#import "LocalProxyDemoController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    RequestDemoController *requestVC = [[RequestDemoController alloc] init];
    requestVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Request"
                                                        image:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                                                          tag:0];
    
    Http3DemoController *http3VC = [[Http3DemoController alloc] init];
    http3VC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"HTTP/3"
                                                      image:[UIImage systemImageNamed:@"bolt.circle"]
                                                        tag:1];

    LocalProxyDemoController *localProxyVC = [[LocalProxyDemoController alloc] init];
    localProxyVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"LocalProxy"
                                                           image:[UIImage systemImageNamed:@"network"]
                                                             tag:2];

    WkWebViewDemoController *webViewVC = [[WkWebViewDemoController alloc] init];
    webViewVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"WebView"
                                                        image:[UIImage systemImageNamed:@"safari"]
                                                          tag:3];
    
    self.viewControllers = @[[[UINavigationController alloc] initWithRootViewController:requestVC],
                           [[UINavigationController alloc] initWithRootViewController:http3VC],
                           [[UINavigationController alloc] initWithRootViewController:localProxyVC],
                           [[UINavigationController alloc] initWithRootViewController:webViewVC]];
}

@end
