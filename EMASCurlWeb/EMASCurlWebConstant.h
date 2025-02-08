//
//  EMASCurlWebConstant.h
//  EMASCurl
//
//  Created by xuyecan on 2025/2/5.
//

#import <Foundation/Foundation.h>

#define LimitVersion 13.0

NS_ASSUME_NONNULL_BEGIN

typedef void(^EMASCurlNetRedirectDecisionCallback)(BOOL);
typedef void(^EMASCurlNetResponseCallback)(NSURLResponse * _Nonnull response);
typedef void(^EMASCurlNetDataCallback)(NSData * _Nonnull data);
typedef void(^EMASCurlNetSuccessCallback)(void);
typedef void(^EMASCurlNetFailCallback)(NSError * _Nonnull error);
typedef void(^EMASCurlNetRedirectCallback)(NSURLResponse * _Nonnull response,
                                     NSURLRequest * _Nonnull redirectRequest,
                                     EMASCurlNetRedirectDecisionCallback redirectDecisionCallback);

NS_ASSUME_NONNULL_END
