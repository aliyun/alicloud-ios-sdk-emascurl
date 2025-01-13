//
//  EMASCurlNetworkSession.h

#import <Foundation/Foundation.h>
#import "EMASCurlCacheProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlNetworkSessionConfiguration: NSObject

@property (nonatomic, assign) NSUInteger cacheCountLimit; // 缓存数量限制

@property (nonatomic, assign) NSUInteger cacheCostLimit; // 缓存容量限制

@property (nonatomic, assign) NSUInteger retryLimit; // 最大重试次数

@property (nonatomic, assign) NSTimeInterval networkTimeoutInterval; // 超时时间

@end

typedef NS_ENUM(NSInteger, EMASCurlNetworkDataTaskPriority) {
    EMASCurlNetworkDataTaskPriorityNormal = 1,
    EMASCurlNetworkDataTaskPriorityHigh,
    EMASCurlNetworkDataTaskPriorityVeryHigh,
};

@interface EMASCurlNetworkDataTask : NSObject

@property (nullable, readonly, copy) NSURLRequest  *originalRequest;

@property (nonatomic) EMASCurlNetworkDataTaskPriority dataTaskPriority; // 任务优先级

@property (nonatomic, assign) NSUInteger retryLimit; // 最大重试次数

- (void)resume ;

- (void)cancel ;

@end

NS_CLASS_AVAILABLE_IOS(10_0)
@interface EMASCurlNetworkSession : NSObject

@property (nonatomic, copy, nullable) NSString *mainUrl; // 页面主URL

+ (instancetype)sessionWithConfiguation:(EMASCurlNetworkSessionConfiguration *)configuration ;

- (nullable EMASCurlNetworkDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                                   responseCallback:(EMASCurlNetResponseCallback)responseCallback
                                       dataCallback:(EMASCurlNetDataCallback)dataCallback
                                    successCallback:(EMASCurlNetSuccessCallback)successCallback
                                       failCallback:(EMASCurlNetFailCallback)failCallback
                                   redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback ;
- (nullable EMASCurlNetworkDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                                   responseCallback:(nullable EMASCurlNetResponseCallback)responseCallback
                                   progressCallBack:(nullable EMASCurlNetProgressCallBack)progressCallBack
                                       dataCallback:(EMASCurlNetDataCallback)dataCallback
                                    successCallback:(EMASCurlNetSuccessCallback)successCallback
                                       failCallback:(EMASCurlNetFailCallback)failCallback
                                   redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback ;

/// 是否超过缓存限制
/// @param cost 本地待缓存大小
- (BOOL)isOvercapacityWithCost:(NSUInteger)cost ;

/// 更新当前缓存使用情况
/// @param cost 本次缓存大小
- (void)updateCacheCapacityWithCost:(NSUInteger)cost ;

/// 取消任务
- (void)cancelTask:(EMASCurlNetworkDataTask *)task;

/// 取消所有任务
- (void)cancelAllTasks ;

@end

NS_ASSUME_NONNULL_END

