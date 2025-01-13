//
//  EMASCurlCacheProtocol.h

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^EMASCurlNetRedirectDecisionCallback)(BOOL);
typedef void(^EMASCurlNetResponseCallback)(NSURLResponse * _Nonnull response);
typedef void(^EMASCurlNetDataCallback)(NSData * _Nonnull data);
typedef void(^EMASCurlNetSuccessCallback)(void);
typedef void(^EMASCurlNetFailCallback)(NSError * _Nonnull error);
typedef void(^EMASCurlNetRedirectCallback)(NSURLResponse * _Nonnull response,
                                     NSURLRequest * _Nonnull redirectRequest,
                                     EMASCurlNetRedirectDecisionCallback redirectDecisionCallback);
typedef void(^EMASCurlNetProgressCallBack)(int64_t nowBytes,int64_t total);


/// 匹配器须遵守此协议并实现方法
@protocol EMASCurlResourceMatcherImplProtocol <NSObject>

/// 返回布尔类型，表示是否处理请求
/// @param request EMASCurlCache拦截到的请求
/// 如果此方法返回YES，则需要在下一个方法中回调对应的数据；
/// 如果此方法返回NO，则EMASCurlCache会检查下一个匹配器
- (BOOL)canHandleWithRequest:(NSURLRequest *)request;


/// 在此方法中匹配器回调给EMASCurlCache数据
/// @param request EMASCurlCache拦截到的请求
/// @param responseCallback 回调NSURLResponse对象
/// @param dataCallback 回调NSData对象
/// @param failCallback 回调error对象
/// @param successCallback 匹配成功回调
/// @param redirectCallback 重定向回调
- (void)startWithRequest:(NSURLRequest *)request
        responseCallback:(EMASCurlNetResponseCallback)responseCallback
            dataCallback:(EMASCurlNetDataCallback)dataCallback
            failCallback:(EMASCurlNetFailCallback)failCallback
         successCallback:(EMASCurlNetSuccessCallback)successCallback
        redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback;

@end


/// EMASCurlCache对网络数据进行缓存的代理（推荐使用YYCache）
@protocol EMASCurlURLCacheDelegate <NSObject>

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key;

- (id<NSCoding>)objectForKey:(NSString *)key;

- (void)removeObjectForKey:(NSString *)key;

- (void)removeAllObjects;

@end

NS_ASSUME_NONNULL_END
