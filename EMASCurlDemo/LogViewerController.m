//
//  LogViewerController.m
//  EMASCurlDemo
//
//  Created by Claude Code on 2025-10-30.
//

#import "LogViewerController.h"
#import "LogManager.h"

@interface LogViewerController ()

@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIButton *clearButton;

@end

@implementation LogViewerController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"SDK Logs";
    self.view.backgroundColor = [UIColor whiteColor];

    [self setupNavigationBar];
    [self setupUI];
    [self refreshLogs];

    // 监听日志更新通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(logsDidUpdate:)
                                                 name:LogManagerDidUpdateLogsNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLogs];
}

- (void)setupNavigationBar {
    // Close button
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithTitle:@"Close"
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(closeButtonTapped)];
    self.navigationItem.leftBarButtonItem = closeButton;
}

- (void)setupUI {
    // Log TextView
    self.logTextView = [[UITextView alloc] init];
    self.logTextView.editable = NO;
    self.logTextView.font = [UIFont fontWithName:@"Menlo" size:12];
    if (@available(iOS 13.0, *)) {
        self.logTextView.backgroundColor = [UIColor systemBackgroundColor];
        self.logTextView.textColor = [UIColor labelColor];
    } else {
        self.logTextView.backgroundColor = [UIColor whiteColor];
        self.logTextView.textColor = [UIColor blackColor];
    }
    self.logTextView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.logTextView.layer.borderWidth = 1.0;
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logTextView];

    // Clear Button
    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearButton setTitle:@"Clear Logs" forState:UIControlStateNormal];
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.clearButton addTarget:self action:@selector(clearButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.clearButton];

    // Auto Layout
    [NSLayoutConstraint activateConstraints:@[
        // Log TextView
        [self.logTextView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.logTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.logTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],

        // Clear Button
        [self.clearButton.topAnchor constraintEqualToAnchor:self.logTextView.bottomAnchor constant:8],
        [self.clearButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.clearButton.heightAnchor constraintEqualToConstant:44],
        [self.clearButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];
}

- (void)refreshLogs {
    NSString *logs = [[LogManager sharedInstance] getAllLogsFormatted];
    self.logTextView.text = logs;

    // 自动滚动到底部
    if (self.logTextView.text.length > 0) {
        NSRange bottom = NSMakeRange(self.logTextView.text.length - 1, 1);
        [self.logTextView scrollRangeToVisible:bottom];
    }
}

- (void)logsDidUpdate:(NSNotification *)notification {
    [self refreshLogs];
}

- (void)closeButtonTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)clearButtonTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Logs"
                                                                   message:@"Are you sure you want to clear all logs?"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    UIAlertAction *clearAction = [UIAlertAction actionWithTitle:@"Clear"
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(UIAlertAction * _Nonnull action) {
        [[LogManager sharedInstance] clearAllLogs];
        [self refreshLogs];
    }];

    [alert addAction:cancelAction];
    [alert addAction:clearAction];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
