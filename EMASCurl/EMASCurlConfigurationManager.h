//
//  EMASCurlConfigurationManager.h
//  EMASCurl
//
//  Created by EMASCurl on 2025/01/02.
//

#import <Foundation/Foundation.h>
#import "EMASCurlConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * 管理EMASCurlConfiguration实例的管理器类
 * 通过唯一标识符存储和检索配置
 */
@interface EMASCurlConfigurationManager : NSObject

/**
 * 获取共享管理器实例
 * @return 单例管理器实例
 */
+ (instancetype)sharedManager;

/**
 * 使用唯一标识符存储配置
 * @param configuration 要存储的配置
 * @param configID 配置的唯一标识符
 */
- (void)setConfiguration:(EMASCurlConfiguration *)configuration forID:(NSString *)configID;

/**
 * 通过标识符检索配置
 * @param configID 唯一标识符
 * @return 找到的配置，未找到返回nil
 */
- (nullable EMASCurlConfiguration *)configurationForID:(NSString *)configID;

/**
 * 通过标识符移除配置
 * @param configID 唯一标识符
 */
- (void)removeConfigurationForID:(NSString *)configID;

/**
 * 移除所有存储的配置
 */
- (void)removeAllConfigurations;

/**
 * 获取所有配置标识符
 * @return 配置ID数组
 */
- (NSArray<NSString *> *)allConfigurationIDs;

/**
 * 获取默认配置
 * 当找不到特定配置时使用
 * @return 默认配置
 */
- (EMASCurlConfiguration *)defaultConfiguration;

/**
 * 设置默认配置
 * @param configuration 用作默认的配置
 */
- (void)setDefaultConfiguration:(EMASCurlConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
