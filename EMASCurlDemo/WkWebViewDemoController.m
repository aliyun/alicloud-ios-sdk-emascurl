#import "WkWebViewDemoController.h"
#import <WebKit/WebKit.h>

@interface WkWebViewDemoController ()
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation WkWebViewDemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WebView Demo";
    
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    [self.view addSubview:self.webView];
    
    NSURL *url = [NSURL URLWithString:@"https://www.aliyun.com"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.webView.frame = self.view.bounds;
}

@end
