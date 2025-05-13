#import "WkWebViewDemoController.h"
#import <WebKit/WebKit.h>
#import <EMASCurl/EMASCurl.h>
#import <EMASCurlWeb/EMASCurlWeb.h>
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

    // Add reload button to navigation bar
    UIBarButtonItem *reloadButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(reloadWebView)];
    self.navigationItem.rightBarButtonItem = reloadButton;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];

    NSURLSessionConfiguration *urlSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    [EMASCurlProtocol setDebugLogEnabled:NO];
    [EMASCurlProtocol setBuiltInRedirectionEnabled:NO];
    [EMASCurlProtocol setCacheEnabled:YES];
    // [EMASCurlProtocol setHTTPVersion:HTTP2];
    // [EMASCurlProtocol setDNSResolver:[SampleDnsResolver class]];
    [EMASCurlProtocol installIntoSessionConfiguration:urlSessionConfig];

    EMASCurlWebUrlSchemeHandler *urlSchemeHandler = [[EMASCurlWebUrlSchemeHandler alloc] initWithSessionConfiguration:urlSessionConfig];

    [EMASCurlWebContentLoader initializeInterception];

    [configuration setURLSchemeHandler:urlSchemeHandler forURLScheme:@"http"];
    [configuration setURLSchemeHandler:urlSchemeHandler forURLScheme:@"https"];
    [configuration enableCookieHandler];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    [self.view addSubview:self.webView];

    NSURL *url = [NSURL URLWithString:@"https://m.taobao.com"];
    // NSURL *url = [NSURL URLWithString:@"http://blog.sample.com"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

- (void)reloadWebView {
    [self.webView reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.webView.frame = self.view.safeAreaLayoutGuide.layoutFrame;
}

@end
