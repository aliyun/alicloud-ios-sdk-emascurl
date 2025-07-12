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

    [self setupSession];
    [self setupUI];
}

- (void)setupSession {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 300;

    [EMASCurlProtocol setLogLevel:EMASCurlLogLevelInfo];

    EMASCurlConfiguration *config = [EMASCurlConfiguration defaultConfiguration];
    [config setCacheEnabled:YES];
    [config setBuiltInGzipEnabled:NO];
    [config setBuiltInRedirectionEnabled:NO];
    [EMASCurlProtocol installIntoSessionConfiguration:configuration configuration:config];

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
    NSString *urlString = @"https://m.taobao.com";
    NSURL *url = [NSURL URLWithString:urlString];

    self.resultTextView.text = @""; // Clear previous results
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url];
    [task resume];
}

- (void)uploadButtonTapped {
    NSString *urlString = @"https://httpbin.org/post";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [EMASCurlProtocol setMetricsObserverBlockForRequest:request metricsObserverBlock:^(NSURLRequest * _Nonnull request, BOOL success, NSError * _Nullable error, double nameLookUpTimeMS, double connectTimeMs, double appConnectTimeMs, double preTransferTimeMs, double startTransferTimeMs, double totalTimeMs) {
        NSLog(@"Network Metrics:\n"
              "Success: %d\n"
              "Error: %@\n"
              "DNS Lookup: %.2fms\n"
              "Connect: %.2fms\n"
              "App Connect: %.2fms\n"
              "Pre-transfer: %.2fms\n"
              "Start Transfer: %.2fms\n"
              "Total: %.2fms",
              success, error,
              nameLookUpTimeMS, connectTimeMs, appConnectTimeMs,
              preTransferTimeMs, startTransferTimeMs, totalTimeMs);
    }];
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
