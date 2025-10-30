#import "WkWebViewDemoController.h"
#import <WebKit/WebKit.h>
#import <EMASLocalProxy/EMASLocalProxy.h>
#import <AlicloudHttpDNS/AlicloudHttpDNS.h>
#import "LogViewerController.h"

@interface WkWebViewDemoController () <UITextFieldDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextField *urlTextField;
@property (nonatomic, strong) UIButton *goButton;
@end

@implementation WkWebViewDemoController

#pragma mark - Proxy Configuration

- (BOOL)configureWithLocalProxy:(WKWebViewConfiguration *)configuration {
    // Check if proxy service is ready first
    if (![EMASLocalHttpProxy isProxyReady]) {
        NSLog(@"EMASLocalHttpProxy service is not ready yet");
        return NO;
    }
    
    // Setup DNS resolver with Block-based interface for EMASHttpLocalProxy
    [EMASLocalHttpProxy setDNSResolverBlock:^NSArray<NSString *> *(NSString *hostname) {
        HttpDnsService *httpdns = [HttpDnsService sharedInstance];
        HttpdnsResult* result = [httpdns resolveHostSyncNonBlocking:hostname byIpType:HttpdnsQueryIPTypeAuto];

        if (result && (result.hasIpv4Address || result.hasIpv6Address)) {
            NSMutableArray<NSString *> *allIPs = [NSMutableArray array];
            if (result.hasIpv4Address) {
                [allIPs addObjectsFromArray:result.ips];
            }
            if (result.hasIpv6Address) {
                [allIPs addObjectsFromArray:result.ipv6s];
            }
            NSLog(@"DNS resolved %@ to IPs: %@", hostname, allIPs);
            return allIPs;
        }

        NSLog(@"DNS resolution failed for domain: %@", hostname);
        return nil;
    }];

    // Configure proxy logging and install into WebView configuration
    [EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelInfo];
    BOOL success = [EMASLocalHttpProxy installIntoWebViewConfiguration:configuration];

    if (success) {
        NSLog(@"EMASHttpLocalProxy configured successfully for WebView");
    } else {
        NSLog(@"EMASHttpLocalProxy configuration failed, using default networking");
    }

    return success;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WebView Demo";

    // Add ViewLogs and Reload buttons to navigation bar
    UIBarButtonItem *viewLogsButton = [[UIBarButtonItem alloc] initWithTitle:@"Logs"
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(viewLogsButtonTapped)];

    UIBarButtonItem *reloadButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(reloadWebView)];

    self.navigationItem.rightBarButtonItems = @[reloadButton, viewLogsButton];

    // Status Label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    // URL TextField
    self.urlTextField = [[UITextField alloc] init];
    self.urlTextField.placeholder = @"Enter URL (e.g., https://m.taobao.com)";
    self.urlTextField.text = @"https://m.taobao.com";
    self.urlTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.urlTextField.font = [UIFont systemFontOfSize:14];
    self.urlTextField.delegate = self;
    self.urlTextField.keyboardType = UIKeyboardTypeURL;
    self.urlTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.urlTextField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.urlTextField];

    // Go Button
    self.goButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.goButton setTitle:@"Go" forState:UIControlStateNormal];
    self.goButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.goButton addTarget:self action:@selector(goButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.goButton];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];

    BOOL proxyConfigured = NO;
    // iOS 17.0+: Use EMASHttpLocalProxy for optimized proxy-based networking
    if (@available(iOS 17.0, *)) {
        proxyConfigured = [self configureWithLocalProxy:configuration];
    } else {
        // iOS < 17.0: Use standard WKWebView without any special networking
        NSLog(@"iOS < 17.0: Using standard WebView without proxy");
    }

    // Update status label based on installation result
    if (@available(iOS 17.0, *)) {
        if (proxyConfigured) {
            self.statusLabel.text = @"LocalProxy: Installed ✓";
            self.statusLabel.textColor = [UIColor systemGreenColor];
        } else {
            self.statusLabel.text = @"LocalProxy: Installation Failed";
            self.statusLabel.textColor = [UIColor systemRedColor];
        }
    } else {
        self.statusLabel.text = @"LocalProxy: Not Available (iOS < 17.0)";
        self.statusLabel.textColor = [UIColor systemGrayColor];
    }

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    [self.view addSubview:self.webView];

    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        // Status Label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.statusLabel.heightAnchor constraintEqualToConstant:20],

        // URL TextField
        [self.urlTextField.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.urlTextField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.urlTextField.heightAnchor constraintEqualToConstant:36],

        // Go Button
        [self.goButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.goButton.leadingAnchor constraintEqualToAnchor:self.urlTextField.trailingAnchor constant:8],
        [self.goButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.goButton.heightAnchor constraintEqualToConstant:36],
        [self.goButton.widthAnchor constraintEqualToConstant:50]
    ]];

    NSURL *url = [NSURL URLWithString:@"https://m.taobao.com"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

- (void)reloadWebView {
    [self.webView reload];
}

- (void)viewLogsButtonTapped {
    LogViewerController *logViewer = [[LogViewerController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:logViewer];
    navController.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)goButtonTapped {
    [self loadURLFromTextField];
}

- (void)loadURLFromTextField {
    NSString *urlString = self.urlTextField.text;
    if (urlString.length == 0) {
        return;
    }

    // Add https:// if no scheme is provided
    if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"]) {
        urlString = [@"https://" stringByAppendingString:urlString];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        [self.webView loadRequest:request];
        [self.urlTextField resignFirstResponder];
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self loadURLFromTextField];
    return YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // WebView frame will be adjusted to account for status label and URL input
    CGRect safeArea = self.view.safeAreaLayoutGuide.layoutFrame;
    CGFloat topControlsHeight = 20 + 8 + 36 + 8; // status label height + padding + url field height + padding
    self.webView.frame = CGRectMake(safeArea.origin.x,
                                   safeArea.origin.y + topControlsHeight,
                                   safeArea.size.width,
                                   safeArea.size.height - topControlsHeight);
}


@end
