//
//  EMASCurlNetworkManager.h
//

#import <Foundation/Foundation.h>
#import "EMASCurlWebConstant.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSInteger RequestTaskIdentifier;

@interface EMASCurlWebRequestExecutor : NSObject

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration;

- (RequestTaskIdentifier)startWithRequest:(NSURLRequest *)request
                         responseCallback:(EMASCurlNetResponseCallback)responseCallback
                             dataCallback:(EMASCurlNetDataCallback)dataCallback
                          successCallback:(EMASCurlNetSuccessCallback)successCallback
                             failCallback:(EMASCurlNetFailCallback)failCallback
                         redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback;

- (void)cancelWithRequestIdentifier:(RequestTaskIdentifier)requestTaskIdentifier;

@end

NS_ASSUME_NONNULL_END
