//
//  ViewController.m
//  EMASCurlDemo
//
//  Created by xin yu on 2024/9/23.
//

#import "ViewController.h"
#import <EMASCurl/EMASCurl.h>
#import <AlicloudHttpDNS/AlicloudHttpDNS.h>

@interface MyDNSResolver : NSObject <EMASCurlProtocolDNSResolver>

@end

@implementation MyDNSResolver

+ (NSString *)resolveDomain:(NSString *)domain {
    HttpDnsService *httpdns = [HttpDnsService sharedInstance];
    HttpdnsResult* result = [httpdns resolveHostSyncNonBlocking:domain byIpType:HttpdnsQueryIPTypeBoth];
    NSLog(@"httpdns resolve result: %@", result);
    if (result) {
        if(result.hasIpv4Address || result.hasIpv6Address) {
            NSMutableArray<NSString *> *allIPs = [NSMutableArray array];
            if (result.hasIpv4Address) {
                [allIPs addObjectsFromArray:result.ips];
            }
            if (result.hasIpv6Address) {
                [allIPs addObjectsFromArray:result.ipv6s];
            }
            NSString *combinedIPs = [allIPs componentsJoinedByString:@","];
            return combinedIPs;
        }
    }
    return nil;
}

@end

@interface ViewController ()

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSURLSessionDataTask *dataTask;

@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) NSMutableURLRequest *request;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self configUrlSessionUsingEmasNet];
}

- (void)configUrlSessionUsingEmasNet {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];

    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    [EMASCurlProtocol setDNSResolver:[MyDNSResolver class]];
    // [EMASCurlProtocol setHTTPVersion:HTTP2];
    // [EMASCurlProtocol setHTTPVersion:HTTP3];

    _session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:[NSOperationQueue mainQueue]];
    _request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://httpbin.org/anything"]];
}

- (IBAction)onNormalRequestClick:(id)sender {
    [self sendNormalRequest];
}

- (IBAction)cancelDataTask:(id)sender {
    [self.dataTask cancel];
}

- (void)sendNormalRequest {
    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:self.request
                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Request failed due to error: %@", error.localizedDescription);
            return;
        }

        NSLog(@"Response : %@", response);

        NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"Response body: %@", body);
    }];
    self.dataTask = dataTask;
    [dataTask resume];
}

- (IBAction)onContinueRequestClick:(id)sender {
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.1
                                             target:self
                                           selector:@selector(sendContinueRequest)
                                           userInfo:nil
                                            repeats:YES];
    self.timer = timer;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

- (IBAction)cancelContinueRequest:(id)sender {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)sendContinueRequest {
    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:self.request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Request failed due to error: %@", error.localizedDescription);
            return;
        }

        NSLog(@"Response : %@", response);

        NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"Response body: %@", body);
    }];
    [dataTask resume];
}

@end
