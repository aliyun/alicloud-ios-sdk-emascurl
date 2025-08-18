#import "LocalProxyDemoController.h"
#import <EMASLocalProxy/EMASLocalHttpProxy.h>

@interface LocalProxyDemoController () <NSURLSessionDataDelegate>
@property (nonatomic, strong) UIButton *getButton;
@property (nonatomic, strong) UIButton *uploadButton;
@property (nonatomic, strong) UIButton *cacheButton;
@property (nonatomic, strong) UIButton *timeoutButton;
@property (nonatomic, strong) UIButton *proxyToggleButton;
@property (nonatomic, strong) UITextView *resultTextView;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL proxyEnabled;
@end

@implementation LocalProxyDemoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Local Proxy Demo";
    self.view.backgroundColor = [UIColor whiteColor];
    self.proxyEnabled = YES;

    [self setupSession];
    [self setupUI];
}

- (void)setupSession {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 300;

    if (@available(iOS 17.0, *)) {
        if ([EMASLocalHttpProxy isProxyReady]) {
            BOOL success = [EMASLocalHttpProxy installIntoUrlSessionConfiguration:configuration];
            NSLog(@"Local proxy installation: %@", success ? @"SUCCESS" : @"FAILED");
        }
    }

    self.session = [NSURLSession sessionWithConfiguration:configuration
                                               delegate:self
                                          delegateQueue:[NSOperationQueue mainQueue]];
}

- (void)setupUI {
    // Proxy Toggle Button
    self.proxyToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self updateProxyToggleButtonTitle];
    self.proxyToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.proxyToggleButton addTarget:self action:@selector(proxyToggleButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.proxyToggleButton];

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
        // Proxy Toggle Button
        [self.proxyToggleButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.proxyToggleButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.proxyToggleButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.proxyToggleButton.heightAnchor constraintEqualToConstant:44],

        // Get Button
        [self.getButton.topAnchor constraintEqualToAnchor:self.proxyToggleButton.bottomAnchor constant:12],
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

- (void)updateProxyToggleButtonTitle {
    NSString *title = [NSString stringWithFormat:@"Local Proxy: %@ (Tap to Toggle)",
                      self.proxyEnabled ? @"ENABLED" : @"DISABLED"];
    [self.proxyToggleButton setTitle:title forState:UIControlStateNormal];
    self.proxyToggleButton.backgroundColor = self.proxyEnabled ? [UIColor systemGreenColor] : [UIColor systemRedColor];
    [self.proxyToggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.proxyToggleButton.layer.cornerRadius = 8.0;
}

- (void)proxyToggleButtonTapped {
    self.proxyEnabled = !self.proxyEnabled;
    [self updateProxyToggleButtonTitle];
    [self setupSession];

    NSString *statusMessage = [NSString stringWithFormat:@"Local Proxy %@\n\n",
                              self.proxyEnabled ? @"ENABLED" : @"DISABLED"];
    self.resultTextView.text = statusMessage;
}

- (void)getButtonTapped {
    NSString *urlString = @"http://httpbin.org/get";
    NSURL *url = [NSURL URLWithString:urlString];

    NSString *proxyStatus = self.proxyEnabled ? @"ENABLED" : @"DISABLED";
    self.resultTextView.text = [NSString stringWithFormat:@"=== GET Request Demo ===\nProxy: %@\nURL: %@\n\n=== Response ===\n", proxyStatus, urlString];
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

    NSString *proxyStatus = self.proxyEnabled ? @"ENABLED" : @"DISABLED";
    self.resultTextView.text = [NSString stringWithFormat:@"=== Upload Request Demo ===\nProxy: %@\nURL: %@\nMethod: POST\nData: %@\n\n=== Response ===\n", proxyStatus, urlString, sampleText];
    NSURLSessionUploadTask *uploadTask = [self.session uploadTaskWithRequest:request fromData:uploadData];
    [uploadTask resume];
}

- (void)cacheButtonTapped {
    NSString *urlString = @"https://httpbin.org/cache/300";
    NSURL *url = [NSURL URLWithString:urlString];

    NSString *proxyStatus = self.proxyEnabled ? @"ENABLED" : @"DISABLED";
    self.resultTextView.text = [NSString stringWithFormat:@"=== Testing Cache (Making same request twice) ===\nProxy: %@\n\n=== First Request ===\n", proxyStatus];

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

    NSString *proxyStatus = self.proxyEnabled ? @"ENABLED" : @"DISABLED";
    self.resultTextView.text = [NSString stringWithFormat:@"=== Testing Timeout (10s delay vs 5s timeout) ===\nProxy: %@\n", proxyStatus];

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
            self.resultTextView.text = [self.resultTextView.text stringByAppendingString:@"\n=== Request Completed Successfully ===\n(Check console for detailed proxy logs)"];
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
