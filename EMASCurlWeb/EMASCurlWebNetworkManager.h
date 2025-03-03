//
//  EMASCurlNetworkSession.h
//

#import <Foundation/Foundation.h>
#import "EMASCurlWebDataTask.h"

NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlWebNetworkManager : NSObject

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration;

- (nullable EMASCurlNetworkDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                                        responseCallback:(nullable EMASCurlNetResponseCallback)responseCallback
                                            dataCallback:(EMASCurlNetDataCallback)dataCallback
                                         successCallback:(EMASCurlNetSuccessCallback)successCallback
                                            failCallback:(EMASCurlNetFailCallback)failCallback
                                        redirectCallback:(EMASCurlNetRedirectCallback)redirectCallback;

- (void)cancelTask:(EMASCurlNetworkDataTask *)task;
- (void)cancelAllTasks;

@end

NS_ASSUME_NONNULL_END
