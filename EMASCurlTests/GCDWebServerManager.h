//
//  GCDWebServerManager.h
//  EMASCurlTests
//
//  Created by xin yu on 2024/10/28.
//

#ifndef GCDWebServerManager_h
#define GCDWebServerManager_h
// GCDWebServerManager.h
#import <Foundation/Foundation.h>

#define EMASCURL_TESTPORT @"12345"
#define EMASCURL_TESTDATA @"a=1&b=2"
#define EMASCURL_TESTHTML @"<html><body><h1>Hello, World!</h1></body></html>"

@interface GCDWebServerManager : NSObject

+ (instancetype)sharedManager;
- (void)startServer;
- (void)stopServer;

@end

#endif /* GCDWebServerManager_h */
