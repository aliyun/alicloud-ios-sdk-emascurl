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

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self configUrlSessionUsingEmasNet];
}

- (void)configUrlSessionUsingEmasNet {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];

    [EMASCurlProtocol setDNSResolver:[MyDNSResolver class]];
    [EMASCurlProtocol setDebugLogEnabled:YES];
    [EMASCurlProtocol installIntoSessionConfiguration:config];
    // [EMASCurlProtocol activateHttp2];
    // [EMASCurlProtocol activateHttp3];

    _session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:[NSOperationQueue mainQueue]];
}

- (IBAction)onNormalRequestClick:(id)sender {
    [self sendNormalRequest];
}

- (void)sendNormalRequest {
    NSURL *url = [NSURL URLWithString:@"https://httpbin.org/anything"];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
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
