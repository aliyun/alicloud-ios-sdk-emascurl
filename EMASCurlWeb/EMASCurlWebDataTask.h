//
//  EMASCurlWebDataTask.h
//  EMASCurl
//
//  Created by xuyecan on 2025/2/5.
//

#import <Foundation/Foundation.h>
#import "EMASCurlWebRequestExecutor.h"

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlNetworkDataTask : NSObject

// 回调
@property (nonatomic, copy) EMASCurlNetResponseCallback responseCallback;
@property (nonatomic, copy) EMASCurlNetDataCallback dataCallback;
@property (nonatomic, copy) EMASCurlNetSuccessCallback successCallback;
@property (nonatomic, copy) EMASCurlNetFailCallback failCallback;
@property (nonatomic, copy) EMASCurlNetRedirectCallback redirectCallback;

@property (nonatomic, copy) void (^retryHandler)(void);
@property (nonatomic, copy) void (^cancelHandler)(void);

@property (nonatomic, weak, nullable) EMASCurlWebRequestExecutor *networkManagerWeakRef;

@property (nonatomic, assign) NSUInteger currentRetryCount;
@property (nullable, readwrite, copy) NSURLRequest *originalRequest;

- (instancetype)initWithRequest:(NSURLRequest *)request;
- (void)resume;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
