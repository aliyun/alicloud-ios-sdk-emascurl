#import "WkWebViewDemoController.h"
#import "NetworkCache.h"
#import <WebKit/WebKit.h>
#import <EMASCurl/EMASCurl.h>

@interface WkWebViewDemoController ()
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation WkWebViewDemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WebView Demo";
    
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.loader.enable = YES;

    [JDCache shareInstance].netCache = [[NetworkCache alloc] initWithName:@"emas.curl.demo.cache"];

    NSURLSessionConfiguration *urlSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol installIntoSessionConfiguration:urlSessionConfig];

    [[JDNetworkManager shareManager] configURLSession:urlSessionConfig];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    [self.view addSubview:self.webView];
    
    NSURL *url = [NSURL URLWithString:@"https://mooc1-api.chaoxing.com/mooc-ans/exam/test/transfer/examlist?cxanalyzetag=hp"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.webView.frame = self.view.bounds;
}

@end
