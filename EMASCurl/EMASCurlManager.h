//
//  MultiCurlManager.h
//  EMASCurl
//
//  Created by xuyecan on 2024/12/9.
//

#import <Foundation/Foundation.h>
#import <curl/curl.h>

@interface EMASCurlManager : NSObject

+ (instancetype)sharedInstance;

- (void)enqueueNewEasyHandle:(CURL *)easyHandle completion:(void (^)(BOOL, NSError *))completion;

@end
