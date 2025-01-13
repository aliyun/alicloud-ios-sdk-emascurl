//
//  EMASCurlNetworkOperationQueue.h

#import <Foundation/Foundation.h>
#import "EMASCurlCacheProtocol.h"
#import "EMASCurlNetworkSession.h"

NS_ASSUME_NONNULL_BEGIN

@protocol EMASCurlNetworkURLCacheHandle <NSObject>

/// 是否启用缓存
- (BOOL)URLCacheEnable;

/// 是否超过缓存限制
/// @param cost 本地待缓存大小
- (BOOL)isOvercapacityWithCost:(NSUInteger)cost ;

/// 更新当前缓存使用情况
/// @param cost 本次缓存大小
- (void)updateCacheCapacityWithCost:(NSUInteger)cost ;

@end


@interface EMASCurlNetworkAsyncOperation : NSOperation

@property (nonatomic, copy) EMASCurlNetResponseCallback responseCallback;
@property (nonatomic, copy) EMASCurlNetDataCallback dataCallback;
@property (nonatomic, copy) EMASCurlNetSuccessCallback successCallback;
@property (nonatomic, copy) EMASCurlNetFailCallback failCallback;
@property (nonatomic, copy) EMASCurlNetRedirectCallback redirectCallback;
@property (nonatomic, copy) EMASCurlNetProgressCallBack progressCallback;
@property (nonatomic, weak) id<EMASCurlNetworkURLCacheHandle> URLCacheHandler;

- (instancetype)initWithRequest:(NSURLRequest *)request canCache:(BOOL)canCache;

@end


@interface EMASCurlNetworkOperationQueue : NSObject

+ (instancetype)defaultQueue ;

- (void)addOperation:(EMASCurlNetworkAsyncOperation *)operation ;

@end

NS_ASSUME_NONNULL_END
