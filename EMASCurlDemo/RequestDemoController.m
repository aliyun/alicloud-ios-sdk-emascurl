#import "RequestDemoController.h"
#import <EMASCurl/EMASCurl.h>

@interface RequestDemoController ()
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

    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol installIntoSessionConfiguration:configuration];

    self.session = [NSURLSession sessionWithConfiguration:configuration];
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
    NSString *urlString = @"https://httpbin.org/get";
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.resultTextView.text = [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
            });
            return;
        }

        NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.resultTextView.text = result;
        });
    }];

    [task resume];
}

- (void)uploadButtonTapped {
    NSString *urlString = @"https://httpbin.org/post";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request.HTTPMethod = @"POST";

    // Create sample data to upload
    NSString *sampleText = @"Hello, this is a test upload!";
    NSData *uploadData = [sampleText dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSessionUploadTask *uploadTask = [self.session uploadTaskWithRequest:request
                                                             fromData:uploadData
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.resultTextView.text = [NSString stringWithFormat:@"Upload Error: %@", error.localizedDescription];
            });
            return;
        }

        NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.resultTextView.text = result;
        });
    }];

    [uploadTask resume];
}

@end
