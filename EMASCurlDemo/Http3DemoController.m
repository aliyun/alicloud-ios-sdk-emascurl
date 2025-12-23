#import "Http3DemoController.h"
#import <EMASCurl/EMASCurl.h>
#import "LogViewerController.h"

@interface Http3DemoController () <NSURLSessionDataDelegate>
@property (nonatomic, strong) UIButton *getButton;
@property (nonatomic, strong) UITextView *resultTextView;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *lastProtocolName;
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

    __weak typeof(self) weakSelf = self;
    curlConfig.transactionMetricsObserver = ^(NSURLRequest * _Nonnull request, BOOL success, NSError * _Nullable error, EMASCurlTransactionMetrics * _Nonnull metrics) {
        weakSelf.lastProtocolName = metrics.networkProtocolName;
        
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

        [self.resultTextView.topAnchor constraintEqualToAnchor:self.getButton.bottomAnchor constant:20],
        [self.resultTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.resultTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.resultTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
}

- (void)getButtonTapped {
    NSString *urlString = @"https://cloudflare-quic.com/";
    NSURL *url = [NSURL URLWithString:urlString];

    self.lastProtocolName = nil;
    self.resultTextView.text = [NSString stringWithFormat:@"请求中...\nURL: %@\n", urlString];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url];
    [task resume];
}

- (NSString *)protocolExplanation:(NSString *)protocol {
    if ([protocol isEqualToString:@"http/3"]) {
        return @"✅ 使用 HTTP/3 (QUIC) 协议";
    } else if ([protocol isEqualToString:@"http/2"]) {
        return @"⚠️ 使用 HTTP/2 协议\n原因: 目标服务器不支持HTTP/3，或EMASCurl未使用HTTP3版本";
    } else if ([protocol isEqualToString:@"http/1.1"]) {
        return @"⚠️ 使用 HTTP/1.1 协议\n原因: 目标服务器不支持HTTP/3和HTTP/2，或EMASCurl未使用HTTP3版本";
    } else {
        return [NSString stringWithFormat:@"❓ 使用 %@ 协议", protocol ?: @"未知"];
    }
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
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
        NSString *protocolInfo = [self protocolExplanation:self.lastProtocolName];
        NSString *header = [NSString stringWithFormat:@"=== 协议信息 ===\n%@\n\n=== 请求结果 ===\n", protocolInfo];
        
        if (error) {
            self.resultTextView.text = [header stringByAppendingFormat:@"❌ 请求失败: %@", error.localizedDescription];
        } else {
            NSString *currentText = self.resultTextView.text;
            // 移除 "请求中..." 前缀
            NSRange range = [currentText rangeOfString:@"请求中...\n"];
            if (range.location != NSNotFound) {
                currentText = [currentText substringFromIndex:range.location + range.length];
            }
            self.resultTextView.text = [header stringByAppendingString:currentText];
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
