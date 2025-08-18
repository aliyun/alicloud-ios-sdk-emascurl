#import "RequestDemoController.h"
#import <EMASCurl/EMASCurl.h>

@interface RequestDemoController () <NSURLSessionDataDelegate>
@property (nonatomic, strong) UIButton *getButton;
@property (nonatomic, strong) UIButton *uploadButton;
@property (nonatomic, strong) UIButton *cacheButton;
@property (nonatomic, strong) UIButton *timeoutButton;
@property (nonatomic, strong) UITextView *resultTextView;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation RequestDemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Request Demo";
    self.view.backgroundColor = [UIColor whiteColor];

    [self setupSession];
    [self setupUI];
}

- (void)setupSession {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 300;

    [EMASCurlProtocol setLogLevel:EMASCurlLogLevelInfo];
    [EMASCurlProtocol setCacheEnabled:YES];
    [EMASCurlProtocol setBuiltInRedirectionEnabled:NO];

    // 设置全局综合性能指标回调（推荐使用）- 基本等价于URLSessionTaskTransactionMetrics
    [EMASCurlProtocol setGlobalTransactionMetricsObserverBlock:^(NSURLRequest * _Nonnull request, BOOL success, NSError * _Nullable error, EMASCurlTransactionMetrics * _Nonnull metrics) {
        NSLog(@"全局综合性能指标 [%@]:\n"
              "成功: %d\n"
              "错误: %@\n"
              "获取开始: %@\n"
              "域名解析开始: %@\n"
              "域名解析结束: %@\n"
              "连接开始: %@\n"
              "安全连接开始: %@\n"
              "安全连接结束: %@\n"
              "连接结束: %@\n"
              "请求开始: %@\n"
              "请求结束: %@\n"
              "响应开始: %@\n"
              "响应结束: %@\n"
              "协议名称: %@\n"
              "代理连接: %@\n"
              "重用连接: %@\n"
              "请求头字节数: %ld\n"
              "响应头字节数: %ld\n"
              "本地地址: %@:%ld\n"
              "远程地址: %@:%ld\n"
              "TLS协议版本: %@\n"
              "TLS密码套件: %@\n",
              request.URL.absoluteString,
              success, error,
              metrics.fetchStartDate,
              metrics.domainLookupStartDate,
              metrics.domainLookupEndDate,
              metrics.connectStartDate,
              metrics.secureConnectionStartDate,
              metrics.secureConnectionEndDate,
              metrics.connectEndDate,
              metrics.requestStartDate,
              metrics.requestEndDate,
              metrics.responseStartDate,
              metrics.responseEndDate,
              metrics.networkProtocolName ?: @"未知",
              metrics.proxyConnection ? @"是" : @"否",
              metrics.reusedConnection ? @"是" : @"否",
              (long)metrics.requestHeaderBytesSent,
              (long)metrics.responseHeaderBytesReceived,
              metrics.localAddress ?: @"未知", (long)metrics.localPort,
              metrics.remoteAddress ?: @"未知", (long)metrics.remotePort,
              metrics.tlsProtocolVersion ?: @"未使用",
              metrics.tlsCipherSuite ?: @"未使用");
    }];

    [EMASCurlProtocol setConnectTimeoutInterval:3];
    [EMASCurlProtocol installIntoSessionConfiguration:configuration];

    self.session = [NSURLSession sessionWithConfiguration:configuration
                                               delegate:self
                                          delegateQueue:[NSOperationQueue mainQueue]];
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
    NSString *urlString = @"https://httpbin.org/get";
    NSURL *url = [NSURL URLWithString:urlString];

    self.resultTextView.text = [NSString stringWithFormat:@"=== GET Request Demo ===\nURL: %@\n\n=== Response ===\n", urlString];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url];
    [task resume];
}

- (void)uploadButtonTapped {
    NSString *urlString = @"https://httpbin.org/post";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];

    // 注意：使用在viewDidLoad中设置的全局性能指标回调，无需为每个请求单独设置
    request.HTTPMethod = @"POST";

    // Create sample data to upload
    NSString *sampleText = @"Hello, this is a test upload!";
    NSData *uploadData = [sampleText dataUsingEncoding:NSUTF8StringEncoding];

    self.resultTextView.text = [NSString stringWithFormat:@"=== Upload Request Demo ===\nURL: %@\nMethod: POST\nData: %@\n\n=== Response ===\n", urlString, sampleText];
    NSURLSessionUploadTask *uploadTask = [self.session uploadTaskWithRequest:request fromData:uploadData];
    [uploadTask resume];
}

- (void)cacheButtonTapped {
    NSString *urlString = @"https://httpbin.org/cache/300"; // cacheable for 5 minutes
    NSURL *url = [NSURL URLWithString:urlString];

    self.resultTextView.text = @"=== Testing Cache (Making same request twice) ===\n\n=== First Request ===\n";

    // First request
    NSURLSessionDataTask *firstTask = [self.session dataTaskWithURL:url
                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.resultTextView.text = [self.resultTextView.text stringByAppendingFormat:@"Status: %ld\n\n=== Second Request (should hit cache) ===\n", (long)httpResponse.statusCode];

            // Second request immediately after
            NSURLSessionDataTask *secondTask = [self.session dataTaskWithURL:url];
            [secondTask resume];
        });
    }];
    [firstTask resume];
}

- (void)timeoutButtonTapped {
    NSString *urlString = @"https://httpbin.org/delay/10"; // 10 second delay
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request.timeoutInterval = 5; // 5 second timeout

    self.resultTextView.text = @"=== Testing Timeout (10s delay vs 5s timeout) ===\n";

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request];
    [task resume];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    // Called when the request first receives a response
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

    NSUInteger code = 0;
    if (httpResponse) {
        code = httpResponse.statusCode;
    }

    NSLog(@">>> %@ didRecievedResponse - %lu", dataTask.currentRequest.URL.absoluteString, code);

    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // Called as data arrives
    NSString *receivedString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    self.resultTextView.text = [self.resultTextView.text stringByAppendingString:receivedString];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSLog(@">>> %@ didComplete - ", task.currentRequest.URL.absoluteString);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (error) {
            self.resultTextView.text = [self.resultTextView.text stringByAppendingFormat:@"\n=== Error ===\n%@", error.localizedDescription];
        } else {
            self.resultTextView.text = [self.resultTextView.text stringByAppendingString:@"\n=== Request Completed Successfully ===\n(Check console for detailed EMASCurl metrics)"];
        }
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {

    NSLog(@">>> %@ willRedirect - ", task.currentRequest.URL.absoluteString);

    // Log redirect information
    NSString *redirectInfo = [NSString stringWithFormat:@"Redirecting from: %@\nTo: %@\n\n",
                            task.originalRequest.URL,
                            request.URL];
    self.resultTextView.text = [self.resultTextView.text stringByAppendingString:redirectInfo];

    // Allow the redirect by passing the new request to the completion handler
    completionHandler(request);
}

@end
