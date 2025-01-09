//
//  ViewController.m
//  EMASCurlDemo
//
//  Created by xin yu on 2024/9/23.
//

#import "ViewController.h"
#import "RequestDemoController.h"
#import "WkWebViewDemoController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    RequestDemoController *requestVC = [[RequestDemoController alloc] init];
    requestVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Request"
                                                        image:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                                                          tag:0];
    
    WkWebViewDemoController *webViewVC = [[WkWebViewDemoController alloc] init];
    webViewVC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"WebView"
                                                        image:[UIImage systemImageNamed:@"safari"]
                                                          tag:1];
    
    self.viewControllers = @[[[UINavigationController alloc] initWithRootViewController:requestVC],
                           [[UINavigationController alloc] initWithRootViewController:webViewVC]];
}

@end
