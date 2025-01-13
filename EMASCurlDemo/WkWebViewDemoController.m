#import "WkWebViewDemoController.h"
#import "NetworkCache.h"
#import <WebKit/WebKit.h>
#import <EMASCurl/EMASCurl.h>
#import <AlicloudHttpDNS/AlicloudHttpDNS.h>


@interface SampleDnsResolver : NSObject<EMASCurlProtocolDNSResolver>

@end

@implementation SampleDnsResolver

+ (NSString *)resolveDomain:(NSString *)domain {
    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
    HttpdnsResult* result = [httpdns resolveHostSyncNonBlocking:domain byIpType:HttpdnsQueryIPTypeAuto];
    if (result) {
        if(result.hasIpv4Address || result.hasIpv6Address) {
            NSMutableArray<NSString *> *allIPs = [NSMutableArray array];
            if (result.hasIpv4Address) {
                [allIPs addObjectsFromArray:result.ips];
            }
            if (result.hasIpv6Address) {
                [allIPs addObjectsFromArray:result.ipv6s];
            }
            NSString *combinedIPs = [allIPs componentsJoinedByString:@","];
            NSLog(@"resolve domain success, domain: %@, resultIps: %@", domain, combinedIPs);
            return combinedIPs;
        }
    }
    NSLog(@"resolve domain failed, domain: %@", domain);
    return nil;
}

@end



@interface WkWebViewDemoController ()
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation WkWebViewDemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WebView Demo";

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.loader.enable = YES;

    [EMASCurlCache shareInstance].netCache = [[NetworkCache alloc] initWithName:@"emas.curl.demo.cache"];

    NSURLSessionConfiguration *urlSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol setBuiltInRedirectionEnabled:NO];
    [EMASCurlProtocol setHTTPVersion:HTTP2];
    [EMASCurlProtocol setDNSResolver:[SampleDnsResolver class]];
    [EMASCurlProtocol installIntoSessionConfiguration:urlSessionConfig];

    [[EMASCurlNetworkManager shareManager] setUpInternalURLSessionWithConfiguration:urlSessionConfig];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    [self.view addSubview:self.webView];
    
    // NSURL *url = [NSURL URLWithString:@"https://www.aliyun.com"];
    NSURL *url = [NSURL URLWithString:@"https://emogine.insights.1688.com/page-targeting/rule-smartservice.console.aliyun.com.json"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.webView.frame = self.view.bounds;
}

@end
