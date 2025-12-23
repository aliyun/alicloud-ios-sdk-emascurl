#import "Http3DemoController.h"
#import <EMASCurl/EMASCurl.h>
#import "LogViewerController.h"

@interface Http3DemoController () <NSURLSessionDataDelegate>
@property (nonatomic, strong) UIButton *getButton;
@property (nonatomic, strong) UIButton *uploadButton;
@property (nonatomic, strong) UIButton *cacheButton;
@property (nonatomic, strong) UIButton *timeoutButton;
@property (nonatomic, strong) UITextView *resultTextView;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation Http3DemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HTTP/3 Demo";
    self.view.backgroundColor = [UIColor whiteColor];

    UIBarButtonItem *viewLogsButton = [[UIBarButtonItem alloc] initWithTitle:@"Logs"
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(viewLogsButtonTapped)];
    self.navigationItem.rightBarButtonItem = viewLogsButton;

    [self setupSession];
    [self setupUI];
}

- (void)setupSession {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 300;

    EMASCurlConfiguration *curlConfig = [EMASCurlConfiguration defaultConfiguration];
    curlConfig.connectTimeoutInterval = 3.0;
    curlConfig.httpVersion = HTTP3;
    curlConfig.cacheEnabled = YES;
    curlConfig.enableBuiltInRedirection = NO;

    curlConfig.transactionMetricsObserver = ^(NSURLRequest * _Nonnull request, BOOL success, NSError * _Nullable error, EMASCurlTransactionMetrics * _Nonnull metrics) {
        NSLog(@"HTTP/3 性能指标 [%@]:\n"
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
    };

    [EMASCurlProtocol setLogLevel:EMASCurlLogLevelInfo];
    [EMASCurlProtocol installIntoSessionConfiguration:configuration withConfiguration:curlConfig];

    self.session = [NSURLSession sessionWithConfiguration:configuration
                                               delegate:self
                                          delegateQueue:[NSOperationQueue mainQueue]];
}

- (void)setupUI {
    self.getButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.getButton setTitle:@"GET Request" forState:UIControlStateNormal];
    self.getButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.getButton addTarget:self action:@selector(getButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.getButton];

    self.uploadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.uploadButton setTitle:@"Upload Request" forState:UIControlStateNormal];
    self.uploadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.uploadButton addTarget:self action:@selector(uploadButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.uploadButton];

    self.cacheButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cacheButton setTitle:@"Sequential Requests (Test Connection Reuse)" forState:UIControlStateNormal];
    self.cacheButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cacheButton addTarget:self action:@selector(cacheButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cacheButton];

    self.timeoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.timeoutButton setTitle:@"Connection Timeout (Invalid Port)" forState:UIControlStateNormal];
    self.timeoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.timeoutButton addTarget:self action:@selector(timeoutButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.timeoutButton];

    self.resultTextView = [[UITextView alloc] init];
    self.resultTextView.editable = NO;
    self.resultTextView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.resultTextView.layer.borderWidth = 1.0;
    self.resultTextView.layer.cornerRadius = 5.0;
    self.resultTextView.font = [UIFont systemFontOfSize:14];
    self.resultTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.resultTextView];

    [NSLayoutConstraint activateConstraints:@[
        [self.getButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.getButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.getButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.getButton.heightAnchor constraintEqualToConstant:44],

        [self.uploadButton.topAnchor constraintEqualToAnchor:self.getButton.bottomAnchor constant:12],
        [self.uploadButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.uploadButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.uploadButton.heightAnchor constraintEqualToConstant:44],

        [self.cacheButton.topAnchor constraintEqualToAnchor:self.uploadButton.bottomAnchor constant:12],
        [self.cacheButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.cacheButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.cacheButton.heightAnchor constraintEqualToConstant:44],

        [self.timeoutButton.topAnchor constraintEqualToAnchor:self.cacheButton.bottomAnchor constant:12],
        [self.timeoutButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.timeoutButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.timeoutButton.heightAnchor constraintEqualToConstant:44],

        [self.resultTextView.topAnchor constraintEqualToAnchor:self.timeoutButton.bottomAnchor constant:20],
        [self.resultTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.resultTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.resultTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
}

- (void)getButtonTapped {
    NSString *urlString = @"https://cloudflare-quic.com/";
    NSURL *url = [NSURL URLWithString:urlString];

    self.resultTextView.text = [NSString stringWithFormat:@"=== HTTP/3 GET Request ===\nURL: %@\n\n=== Response ===\n", urlString];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url];
    [task resume];
}

- (void)uploadButtonTapped {
    NSString *urlString = @"https://cloudflare-quic.com/";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request.HTTPMethod = @"POST";

    NSString *sampleText = @"Hello, HTTP/3 test upload!";
    NSData *uploadData = [sampleText dataUsingEncoding:NSUTF8StringEncoding];

    self.resultTextView.text = [NSString stringWithFormat:@"=== HTTP/3 Upload Request ===\nURL: %@\nMethod: POST\nData: %@\n\n=== Response ===\n", urlString, sampleText];
    NSURLSessionUploadTask *uploadTask = [self.session uploadTaskWithRequest:request fromData:uploadData];
    [uploadTask resume];
}

- (void)cacheButtonTapped {
    NSString *urlString = @"https://cloudflare-quic.com/";
    NSURL *url = [NSURL URLWithString:urlString];

    self.resultTextView.text = @"=== Sequential Requests (Test Connection Reuse) ===\n\n";

    __block int completedCount = 0;
    for (int i = 1; i <= 3; i++) {
        NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            dispatch_async(dispatch_get_main_queue(), ^{
                completedCount++;
                self.resultTextView.text = [self.resultTextView.text stringByAppendingFormat:@"Request #%d: Status %ld\n", completedCount, (long)httpResponse.statusCode];
                if (completedCount == 3) {
                    self.resultTextView.text = [self.resultTextView.text stringByAppendingString:@"\n=== All Requests Completed ===\n(Check logs for connection reuse info)"];
                }
            });
        }];
        [task resume];
    }
}

- (void)timeoutButtonTapped {
    // 请求一个不存在的端口，测试连接超时
    NSString *urlString = @"https://cloudflare-quic.com:12345/";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request.timeoutInterval = 3;

    self.resultTextView.text = @"=== Connection Timeout Test ===\nURL: https://cloudflare-quic.com:12345/\nTimeout: 3s\n\n";

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request];
    [task resume];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSLog(@">>> HTTP/3 %@ didRecievedResponse - %lu", dataTask.currentRequest.URL.absoluteString, (unsigned long)httpResponse.statusCode);
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSString *receivedString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (receivedString) {
        self.resultTextView.text = [self.resultTextView.text stringByAppendingString:receivedString];
    } else {
        self.resultTextView.text = [self.resultTextView.text stringByAppendingFormat:@"[Received %lu bytes binary data]\n", (unsigned long)data.length];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (error) {
            self.resultTextView.text = [self.resultTextView.text stringByAppendingFormat:@"\n=== Error ===\n%@", error.localizedDescription];
        } else {
            self.resultTextView.text = [self.resultTextView.text stringByAppendingString:@"\n=== Request Completed Successfully ===\n"];
        }
    });
}

#pragma mark - ViewLogs

- (void)viewLogsButtonTapped {
    LogViewerController *logViewer = [[LogViewerController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:logViewer];
    navController.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navController animated:YES completion:nil];
}

@end
