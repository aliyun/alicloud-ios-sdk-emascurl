//
//  MultiCurlManager.h
//  EMASCurl
//
//  Created by xuyecan on 2024/12/9.
//

#import <Foundation/Foundation.h>
#import <curl/curl.h>

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlMetricsData : NSObject

// 时间指标 (秒)
@property (nonatomic, assign) double nameLookupTime;
@property (nonatomic, assign) double connectTime;
@property (nonatomic, assign) double appConnectTime;
@property (nonatomic, assign) double preTransferTime;
@property (nonatomic, assign) double startTransferTime;
@property (nonatomic, assign) double totalTime;

// 连接信息
@property (nonatomic, assign) long httpVersion;
@property (nonatomic, copy, nullable) NSString *primaryIP;
@property (nonatomic, assign) long primaryPort;
@property (nonatomic, copy, nullable) NSString *localIP;
@property (nonatomic, assign) long localPort;
@property (nonatomic, assign) long numConnects;
@property (nonatomic, assign) BOOL usedProxy;

// 传输字节数
@property (nonatomic, assign) long requestSize;
@property (nonatomic, assign) long headerSize;
@property (nonatomic, assign) long long uploadBytes;
@property (nonatomic, assign) long long downloadBytes;

@end

@interface EMASCurlManager : NSObject

+ (instancetype)sharedInstance;

- (void)enqueueNewEasyHandle:(CURL *)easyHandle completion:(void (^)(BOOL succeeded, NSError * _Nullable error, EMASCurlMetricsData * _Nullable metrics))completion;

/// 唤醒 multi 事件循环，常用于取消请求后尽快进入回调
- (void)wakeup;

@end

NS_ASSUME_NONNULL_END
