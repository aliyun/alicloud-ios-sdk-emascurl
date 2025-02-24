//
//  EMASCurlWebLogger.m
//  EMASCurl
//
//  Created by xuyecan on 2025/2/5.
//

#import "EMASCurlWebLogger.h"

static BOOL gLogEnabled = NO;

void EMASCurlCacheLog(NSString *format, ...) {
    if (!gLogEnabled) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *logFormat = [@"[EMASCurlWebContentLoader] " stringByAppendingString:format];
    NSString *result = [[NSString alloc] initWithFormat:logFormat arguments:args];
    NSLog(@"%@", result);
    va_end(args);
}

@implementation EMASCurlWebLogger

+ (void)setDebugLogEnabled:(BOOL)enabled {
    gLogEnabled = enabled;
}

@end
