#import "RequestDemoController.h"
#import <EMASCurl/EMASCurl.h>

@interface RequestDemoController () <NSURLSessionDataDelegate>
@property (nonatomic, strong) UIButton *getButton;
@property (nonatomic, strong) UIButton *uploadButton;
@property (nonatomic, strong) UITextView *resultTextView;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation RequestDemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Request Demo";
    self.view.backgroundColor = [UIColor whiteColor];

    // 设置全局综合性能指标回调（推荐使用）- 等价于URLSessionTaskTransactionMetrics
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
    [EMASCurlProtocol installIntoSessionConfiguration:configuration];

    self.session = [NSURLSession sessionWithConfiguration:configuration
                                               delegate:self
                                          delegateQueue:[NSOperationQueue mainQueue]];
}

- (void)setupUI {
    // Get Button
    self.getButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.getButton setTitle:@"GET Request" forState:UIControlStateNormal];
    self.getButton.frame = CGRectMake(20, 100, self.view.bounds.size.width - 40, 44);
    [self.getButton addTarget:self action:@selector(getButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.getButton];

    // Upload Button
    self.uploadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.uploadButton setTitle:@"Upload Request" forState:UIControlStateNormal];
    self.uploadButton.frame = CGRectMake(20, 160, self.view.bounds.size.width - 40, 44);
    [self.uploadButton addTarget:self action:@selector(uploadButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.uploadButton];

    // Result TextView
    self.resultTextView = [[UITextView alloc] initWithFrame:CGRectMake(20, 220, self.view.bounds.size.width - 40, 500)];
    self.resultTextView.editable = NO;
    self.resultTextView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.resultTextView.layer.borderWidth = 1.0;
    self.resultTextView.layer.cornerRadius = 5.0;
    self.resultTextView.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.resultTextView];
}

- (void)getButtonTapped {
    NSString *urlString = @"https://hk.xuyecan1919.tech/api/config";
    NSURL *url = [NSURL URLWithString:urlString];

    self.resultTextView.text = @""; // Clear previous results
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

    self.resultTextView.text = @""; // Clear previous results
    NSURLSessionUploadTask *uploadTask = [self.session uploadTaskWithRequest:request fromData:uploadData];
    [uploadTask resume];
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

    if (error) {
        self.resultTextView.text = [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
    }
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
