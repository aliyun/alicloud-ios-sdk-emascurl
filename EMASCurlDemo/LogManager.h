//
//  LogManager.h
//  EMASCurlDemo
//
//  Created by Claude Code on 2025-10-30.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 日志管理器，用于收集和管理来自EMASCurl和EMASLocalProxy的日志
@interface LogManager : NSObject

/// 获取单例实例
+ (instancetype)sharedInstance;

/// 添加日志条目
/// @param level 日志级别（0=OFF, 1=ERROR, 2=INFO, 3=DEBUG）
/// @param component 组件名称
/// @param message 日志消息
- (void)addLogWithLevel:(NSInteger)level
              component:(NSString *)component
                message:(NSString *)message;

/// 获取所有日志内容（格式化后的字符串）
- (NSString *)getAllLogsFormatted;

/// 清除所有日志
- (void)clearAllLogs;

/// 日志更新通知名称
extern NSNotificationName const LogManagerDidUpdateLogsNotification;

@end

NS_ASSUME_NONNULL_END
