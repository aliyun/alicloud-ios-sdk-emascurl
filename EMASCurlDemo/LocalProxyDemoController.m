#import "LocalProxyDemoController.h"
#import <EMASLocalProxy/EMASLocalProxy.h>
#import <AlicloudHttpDNS/AlicloudHttpDNS.h>

@interface LocalProxyDemoController () <NSURLSessionDataDelegate>
@property (nonatomic, strong) UIButton *getButton;
@property (nonatomic, strong) UIButton *uploadButton;
@property (nonatomic, strong) UIButton *cacheButton;
@property (nonatomic, strong) UIButton *timeoutButton;
@property (nonatomic, strong) UITextView *resultTextView;
@property (atomic, strong) NSURLSession *session;
@end

@implementation LocalProxyDemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Local Proxy Demo";
    self.view.backgroundColor = [UIColor whiteColor];

    // 设置HTTPDNS解析器（全局配置，只需设置一次）
    [self setupDNSResolver];

    // 设置代理日志级别
    [EMASLocalHttpProxy setLogLevel:EMASLocalHttpProxyLogLevelInfo];

    // 立即创建标准session以支持即时的网络请求
    [self createStandardSession];

    // 异步尝试升级到代理session
    [self tryUpgradeToProxySession];

    [self setupUI];
}

- (void)setupDNSResolver {
    // 设置HTTPDNS解析器（类似于WkWebViewDemoController中的模式）
    [EMASLocalHttpProxy setDNSResolverBlock:^NSArray<NSString *> *(NSString *hostname) {
        HttpDnsService *httpdns = [HttpDnsService sharedInstance];
        HttpdnsResult* result = [httpdns resolveHostSyncNonBlocking:hostname byIpType:HttpdnsQueryIPTypeBoth];

        if (result && (result.hasIpv4Address || result.hasIpv6Address)) {
            NSMutableArray<NSString *> *allIPs = [NSMutableArray array];
            if (result.hasIpv4Address) {
                [allIPs addObjectsFromArray:result.ips];
            }
            if (result.hasIpv6Address) {
                [allIPs addObjectsFromArray:result.ipv6s];
            }
            NSLog(@"HTTPDNS解析成功，域名: %@, IP: %@", hostname, allIPs);
            return allIPs;
        }

        NSLog(@"HTTPDNS解析失败，域名: %@", hostname);
        return nil;
    }];
}

- (void)createStandardSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30;
    config.timeoutIntervalForResource = 300;

    self.session = [NSURLSession sessionWithConfiguration:config
                                                 delegate:self
                                            delegateQueue:[NSOperationQueue mainQueue]];
    NSLog(@"创建标准URLSession");
}

- (void)tryUpgradeToProxySession {
    // 延迟1s后检查代理服务状态
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([EMASLocalHttpProxy isProxyReady]) {
            NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
            config.timeoutIntervalForRequest = 30;
            config.timeoutIntervalForResource = 300;

            BOOL success = [EMASLocalHttpProxy installIntoUrlSessionConfiguration:config];

            if (success) {
                @synchronized(self) {
                    // 保存旧session的引用
                    NSURLSession *oldSession = self.session;

                    // 创建新的代理session
                    self.session = [NSURLSession sessionWithConfiguration:config
                                                                 delegate:self
                                                            delegateQueue:[NSOperationQueue mainQueue]];
                    NSLog(@"已升级到代理URLSession");

                    // 优雅地关闭旧session：等待现有任务完成后再关闭
                    // 注意：新的网络请求将使用新的代理session
                    [oldSession finishTasksAndInvalidate];
                }
            } else {
                NSLog(@"代理配置失败，继续使用标准URLSession");
            }
        } else {
            NSLog(@"代理服务未就绪，继续使用标准URLSession");
        }
    });
}

- (void)setupUI {
    // Get Button
    self.getButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.getButton setTitle:@"GET Request" forState:UIControlStateNormal];
    self.getButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.getButton addTarget:self action:@selector(getButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.getButton];

    // Upload Button
    self.uploadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.uploadButton setTitle:@"Upload Request" forState:UIControlStateNormal];
    self.uploadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.uploadButton addTarget:self action:@selector(uploadButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.uploadButton];

    // Cache Button
    self.cacheButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cacheButton setTitle:@"Test Cache (Make Same Request Twice)" forState:UIControlStateNormal];
    self.cacheButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cacheButton addTarget:self action:@selector(cacheButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cacheButton];

    // Timeout Button
    self.timeoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.timeoutButton setTitle:@"Test Timeout (Slow Endpoint)" forState:UIControlStateNormal];
    self.timeoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.timeoutButton addTarget:self action:@selector(timeoutButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.timeoutButton];

    // Result TextView
    self.resultTextView = [[UITextView alloc] init];
    self.resultTextView.editable = NO;
    self.resultTextView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.resultTextView.layer.borderWidth = 1.0;
    self.resultTextView.layer.cornerRadius = 5.0;
    self.resultTextView.font = [UIFont systemFontOfSize:14];
    self.resultTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.resultTextView];

    // Auto Layout Constraints
    [NSLayoutConstraint activateConstraints:@[
        // Get Button
        [self.getButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.getButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.getButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.getButton.heightAnchor constraintEqualToConstant:44],

        // Upload Button
        [self.uploadButton.topAnchor constraintEqualToAnchor:self.getButton.bottomAnchor constant:12],
        [self.uploadButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.uploadButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.uploadButton.heightAnchor constraintEqualToConstant:44],

        // Cache Button
        [self.cacheButton.topAnchor constraintEqualToAnchor:self.uploadButton.bottomAnchor constant:12],
        [self.cacheButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.cacheButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.cacheButton.heightAnchor constraintEqualToConstant:44],

        // Timeout Button
        [self.timeoutButton.topAnchor constraintEqualToAnchor:self.cacheButton.bottomAnchor constant:12],
        [self.timeoutButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.timeoutButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.timeoutButton.heightAnchor constraintEqualToConstant:44],

        // Result TextView
        [self.resultTextView.topAnchor constraintEqualToAnchor:self.timeoutButton.bottomAnchor constant:20],
        [self.resultTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.resultTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.resultTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
}


- (void)getButtonTapped {
    NSString *urlString = @"http://httpbin.org/get";
    NSURL *url = [NSURL URLWithString:urlString];

    self.resultTextView.text = [NSString stringWithFormat:@"=== GET Request Demo ===\nURL: %@\n\n=== Response ===\n", urlString];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url];
    [task resume];
}

- (void)uploadButtonTapped {
    NSString *urlString = @"http://httpbin.org/post";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];

    request.HTTPMethod = @"POST";

    NSString *sampleText = @"Hello from Local Proxy Demo!";
    NSData *uploadData = [sampleText dataUsingEncoding:NSUTF8StringEncoding];

    self.resultTextView.text = [NSString stringWithFormat:@"=== Upload Request Demo ===\nURL: %@\nMethod: POST\nData: %@\n\n=== Response ===\n", urlString, sampleText];
    NSURLSessionUploadTask *uploadTask = [self.session uploadTaskWithRequest:request fromData:uploadData];
    [uploadTask resume];
}

- (void)cacheButtonTapped {
    NSString *urlString = @"https://httpbin.org/cache/300";
    NSURL *url = [NSURL URLWithString:urlString];

    self.resultTextView.text = @"=== Testing Cache (Making same request twice) ===\n\n=== First Request ===\n";

    NSURLSessionDataTask *firstTask = [self.session dataTaskWithURL:url
                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.resultTextView.text = [self.resultTextView.text stringByAppendingFormat:@"Status: %ld\n\n=== Second Request (should hit cache) ===\n", (long)httpResponse.statusCode];

            NSURLSessionDataTask *secondTask = [self.session dataTaskWithURL:url];
            [secondTask resume];
        });
    }];
    [firstTask resume];
}

- (void)timeoutButtonTapped {
    NSString *urlString = @"https://httpbin.org/delay/10";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request.timeoutInterval = 5;

    self.resultTextView.text = @"=== Testing Timeout (10s delay vs 5s timeout) ===\n";

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request];
    [task resume];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

    NSUInteger code = 0;
    if (httpResponse) {
        code = httpResponse.statusCode;
    }

    NSLog(@">>> %@ didRecievedResponse - %lu", dataTask.currentRequest.URL.absoluteString, code);

    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSString *receivedString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    self.resultTextView.text = [self.resultTextView.text stringByAppendingString:receivedString];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSLog(@">>> %@ didComplete - ", task.currentRequest.URL.absoluteString);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (error) {
            self.resultTextView.text = [self.resultTextView.text stringByAppendingFormat:@"\n=== Error ===\n%@", error.localizedDescription];
        } else {
            self.resultTextView.text = [self.resultTextView.text stringByAppendingString:@"\n=== Request Completed Successfully ===\n"];
        }
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {

    NSLog(@">>> %@ willRedirect - ", task.currentRequest.URL.absoluteString);

    NSString *redirectInfo = [NSString stringWithFormat:@"Redirecting from: %@\nTo: %@\n\n",
                            task.originalRequest.URL,
                            request.URL];
    self.resultTextView.text = [self.resultTextView.text stringByAppendingString:redirectInfo];

    completionHandler(request);
}

@end
