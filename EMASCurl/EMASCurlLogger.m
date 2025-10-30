//
//  EMASCurlLogger.m
//  EMASCurl
//
//  Created by xuyecan on 2025/5/23.
//

#import "EMASCurlLogger.h"

@interface EMASCurlLogger ()

@property (atomic, assign) EMASCurlLogLevel currentLogLevel;
@property (atomic, copy, nullable) EMASCurlLogHandlerBlock logHandler;

@end

@implementation EMASCurlLogger

+ (instancetype)sharedLogger {
    static EMASCurlLogger *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[EMASCurlLogger alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 默认日志级别设为ERROR，生产环境较为安全
        _currentLogLevel = EMASCurlLogLevelError;
    }
    return self;
}

+ (void)setLogLevel:(EMASCurlLogLevel)level {
    [EMASCurlLogger sharedLogger].currentLogLevel = level;
}

+ (EMASCurlLogLevel)currentLogLevel {
    return [EMASCurlLogger sharedLogger].currentLogLevel;
}

+ (void)setLogHandler:(nullable EMASCurlLogHandlerBlock)handler {
    [EMASCurlLogger sharedLogger].logHandler = handler;
}

+ (nullable EMASCurlLogHandlerBlock)currentLogHandler {
    return [EMASCurlLogger sharedLogger].logHandler;
}

+ (NSString *)stringForLogLevel:(EMASCurlLogLevel)level {
    switch (level) {
        case EMASCurlLogLevelOff:
            return @"OFF";
        case EMASCurlLogLevelError:
            return @"ERROR";
        case EMASCurlLogLevelInfo:
            return @"INFO";
        case EMASCurlLogLevelDebug:
            return @"DEBUG";
        default:
            return @"UNKNOWN";
    }
}

@end

// 全局函数实现，供宏调用
void EMASCurlLog(EMASCurlLogLevel level, NSString *component, NSString *format, ...) {
    // 检查是否需要记录此级别的日志
    if (level > [EMASCurlLogger currentLogLevel]) {
        return;
    }

    // 获取格式化的消息
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // 检查是否有自定义日志处理器
    EMASCurlLogHandlerBlock handler = [EMASCurlLogger currentLogHandler];
    if (handler) {
        // 使用自定义处理器
        handler(level, component, message);
    } else {
        // 默认使用 NSLog 输出（向后兼容）
        // 生成时间戳
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];

        // 获取日志级别字符串
        NSString *levelString;
        switch (level) {
            case EMASCurlLogLevelOff:
                levelString = @"OFF";
                break;
            case EMASCurlLogLevelError:
                levelString = @"ERROR";
                break;
            case EMASCurlLogLevelInfo:
                levelString = @"INFO";
                break;
            case EMASCurlLogLevelDebug:
                levelString = @"DEBUG";
                break;
            default:
                levelString = @"UNKNOWN";
                break;
        }

        // 输出格式化的日志消息
        NSLog(@"[%@] [%@] [%@] %@", timestamp, levelString, component, message);
    }
}
