//
//  LogManager.m
//  EMASCurlDemo
//
//  Created by Claude Code on 2025-10-30.
//

#import "LogManager.h"

NSNotificationName const LogManagerDidUpdateLogsNotification = @"LogManagerDidUpdateLogsNotification";

@interface LogManager ()

@property (nonatomic, strong) NSMutableArray<NSString *> *logs;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@end

@implementation LogManager

+ (instancetype)sharedInstance {
    static LogManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LogManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logs = [NSMutableArray array];
        _logQueue = dispatch_queue_create("com.emas.demo.logmanager", DISPATCH_QUEUE_SERIAL);

        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateFormat = @"HH:mm:ss.SSS";
    }
    return self;
}

- (void)addLogWithLevel:(NSInteger)level
              component:(NSString *)component
                message:(NSString *)message {
    dispatch_async(self.logQueue, ^{
        if (level == 0 || level > 2) {
            return;
        }

        // 格式化时间戳
        NSString *timestamp = [self.dateFormatter stringFromDate:[NSDate date]];

        // 格式化日志级别
        NSString *levelString;
        switch (level) {
            case 0:
                levelString = @"OFF";
                break;
            case 1:
                levelString = @"ERROR";
                break;
            case 2:
                levelString = @"INFO";
                break;
            case 3:
                levelString = @"DEBUG";
                break;
            default:
                levelString = @"UNKNOWN";
                break;
        }

        // 构建日志条目
        NSString *logEntry = [NSString stringWithFormat:@"[%@] [%@] [%@] %@",
                              timestamp, levelString, component, message];

        NSLog(@"%@", logEntry);
        [self.logs addObject:logEntry];

        // 发送通知
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:LogManagerDidUpdateLogsNotification
                                                                object:nil];
        });
    });
}

- (NSString *)getAllLogsFormatted {
    __block NSString *result = @"";
    dispatch_sync(self.logQueue, ^{
        if (self.logs.count == 0) {
            result = @"No logs available";
        } else {
            result = [self.logs componentsJoinedByString:@"\n"];
        }
    });
    return result;
}

- (void)clearAllLogs {
    dispatch_async(self.logQueue, ^{
        [self.logs removeAllObjects];

        // 发送通知
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:LogManagerDidUpdateLogsNotification
                                                                object:nil];
        });
    });
}

@end
