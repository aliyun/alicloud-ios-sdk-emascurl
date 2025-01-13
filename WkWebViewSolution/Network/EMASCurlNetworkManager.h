//
//  EMASCurlNetworkManager.h

#import <Foundation/Foundation.h>
#import "EMASCurlCacheProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class EMASCurlNetworkAsyncOperation;

@interface EMASCurlNetworkCallBackWorker : NSObject

@end

typedef NSInteger RequestTaskIdentifier;


@interface EMASCurlNetworkManager : NSObject

+ (void)start; // 网络框架预热

+ (instancetype)shareManager;

- (void)setUpInternalURLSessionWithConfiguration:(NSURLSessionConfiguration *)urlSessionConfiguration;

- (RequestTaskIdentifier)startWithRequest:(NSURLRequest *)request
                         responseCallback:(EMASCurlNetResponseCallback)responseCallback
                             dataCallback:(EMASCurlNetDataCallback)dataCallback
                          successCallback:(EMASCurlNetSuccessCallback)successCallback
                             failCallback:(EMASCurlNetFailCallback)failCallback
                         redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback ;

- (RequestTaskIdentifier)startWithRequest:(NSURLRequest *)request
                         responseCallback:(EMASCurlNetResponseCallback)responseCallback
                         progressCallBack:(nullable EMASCurlNetProgressCallBack)progressCallBack
                             dataCallback:(EMASCurlNetDataCallback)dataCallback
                          successCallback:(EMASCurlNetSuccessCallback)successCallback
                             failCallback:(EMASCurlNetFailCallback)failCallback
                         redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback ;

- (void)cancelWithRequestIdentifier:(RequestTaskIdentifier)requestTaskIdentifier ;

@end

NS_ASSUME_NONNULL_END
