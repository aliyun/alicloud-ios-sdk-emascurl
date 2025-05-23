//
//  EMASCurlLogger.h
//  EMASCurl
//
//  Created by xuyecan on 2025/5/23.
//

#ifndef EMASCurlLogger_h
#define EMASCurlLogger_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 日志级别枚举
typedef NS_ENUM(NSInteger, EMASCurlLogLevel) {
    EMASCurlLogLevelOff = 0,      // 禁用所有日志
    EMASCurlLogLevelError = 1,    // 仅错误信息
    EMASCurlLogLevelInfo = 2,     // 信息和错误
    EMASCurlLogLevelDebug = 3,    // 调试信息和以上所有，包括libcurl输出
};

@interface EMASCurlLogger : NSObject

// 获取共享实例
+ (instancetype)sharedLogger;

// 设置全局日志级别
+ (void)setLogLevel:(EMASCurlLogLevel)level;

// 获取当前日志级别
+ (EMASCurlLogLevel)currentLogLevel;

@end

// 便捷的日志记录宏 - 使用全局函数避免宏参数问题
#define EMAS_LOG_ERROR(component, format, ...) \
    EMASCurlLog(EMASCurlLogLevelError, component, format, ##__VA_ARGS__)

#define EMAS_LOG_INFO(component, format, ...) \
    EMASCurlLog(EMASCurlLogLevelInfo, component, format, ##__VA_ARGS__)

#define EMAS_LOG_DEBUG(component, format, ...) \
    EMASCurlLog(EMASCurlLogLevelDebug, component, format, ##__VA_ARGS__)

// 内部使用的函数声明，供宏调用
void EMASCurlLog(EMASCurlLogLevel level, NSString *component, NSString *format, ...);

NS_ASSUME_NONNULL_END

#endif /* EMASCurlLogger_h */
