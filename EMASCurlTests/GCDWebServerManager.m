//
//  GCDWebServerManager.m
//  EMASCurlTests
//
//  Created by xin yu on 2024/10/28.
//

#import <Foundation/Foundation.h>
// GCDWebServerManager.m
#import "GCDWebServerManager.h"
#import <GCDWebServer/GCDWebServer.h>
#import <GCDWebServer/GCDWebServerDataResponse.h>
#import <GCDWebServer/GCDWebServerURLEncodedFormRequest.h>
#import <GCDWebServer/GCDWebServerDataRequest.h>

@interface GCDWebServerManager ()

@property (nonatomic, strong) GCDWebServer *webServer;

@end

@implementation GCDWebServerManager

+ (instancetype)sharedManager {
    static GCDWebServerManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _webServer = [[GCDWebServer alloc] init];

    // Add a GET handler
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/hello"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse *(__kindof GCDWebServerRequest *request) {
        return [GCDWebServerDataResponse responseWithHTML:EMASCURL_TESTHTML];
    }];

    // Add a HEAD handler
    [_webServer addHandlerForMethod:@"HEAD"
                               path:@"/hello"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse *(__kindof GCDWebServerRequest *request) {
        return [GCDWebServerDataResponse responseWithHTML:@""];
    }];

    // Add a POST handler
    [_webServer addHandlerForMethod:@"POST"
                               path:@"/post"
                       requestClass:[GCDWebServerURLEncodedFormRequest class]
                       processBlock:^GCDWebServerResponse *(__kindof GCDWebServerRequest *request) {
        GCDWebServerDataRequest* dataRequest = (GCDWebServerDataRequest*)request;
        NSString *responseText = [[NSString alloc] initWithData:dataRequest.data encoding:NSUTF8StringEncoding];
        return [GCDWebServerDataResponse responseWithHTML:responseText];
    }];

    // Add a PUT handler
    [_webServer addHandlerForMethod:@"PUT"
                               path:@"/put"
                       requestClass:[GCDWebServerDataRequest class]
                       processBlock:^GCDWebServerResponse *(__kindof GCDWebServerRequest *request) {
        GCDWebServerDataRequest* dataRequest = (GCDWebServerDataRequest*)request;
        NSString *responseText = [[NSString alloc] initWithData:dataRequest.data encoding:NSUTF8StringEncoding];
        return [GCDWebServerDataResponse responseWithHTML:responseText];
    }];

    // Add a handler for fixed 302 redirect
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/redirect"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse *(__kindof GCDWebServerRequest *request) {
        NSURL *redirectURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%@/hello", EMASCURL_TESTPORT]];
        GCDWebServerResponse *response = [GCDWebServerResponse responseWithRedirect:redirectURL permanent:NO];
        return response;
    }];

    // Add a GET handler for download
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/download"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse *(__kindof GCDWebServerRequest *request) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *filePath = [mainBundle pathForResource:@"test" ofType:@"txt"];
        NSString *responseText = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:filePath] encoding:NSUTF8StringEncoding];
        return [GCDWebServerDataResponse responseWithHTML:responseText];
    }];

    // Add a GET handler for gzip
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/gzip"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse *(__kindof GCDWebServerRequest *request) {
        GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithHTML:EMASCURL_TESTHTML];
        response.gzipContentEncodingEnabled = YES;
        return response;
    }];

    // Add a GET handler for chunked encoding
    [_webServer addHandlerForMethod:@"GET"
                               path:@"/chunked"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse *(__kindof GCDWebServerRequest *request) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *filePath = [mainBundle pathForResource:@"test" ofType:@"txt"];
        NSString *responseText = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:filePath] encoding:NSUTF8StringEncoding];
        GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithHTML:responseText];
        response.gzipContentEncodingEnabled = YES;
        return response;
    }];

    return self;
}

- (void)startServer {
    [_webServer startWithPort:[EMASCURL_TESTPORT integerValue] bonjourName:nil];
}

- (void)stopServer {
    [_webServer stop];
}

@end
