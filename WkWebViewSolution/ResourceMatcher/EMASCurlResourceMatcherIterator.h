//
//  EMASCurlCacheIterator.h

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import "EMASCurlResourceMatcherManager.h"
#import "EMASCurlUtils.h"

NS_ASSUME_NONNULL_BEGIN
API_AVAILABLE(ios(LimitVersion))

@protocol EMASCurlResourceMatcherIteratorProtocol <NSObject>

- (void)didReceiveResponse:(NSURLResponse *)response urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask;

- (void)didReceiveData:(NSData *)data urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask;

- (void)didFinishWithUrlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask;

- (void)didFailWithError:(NSError *)error urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask;

- (void)didRedirectWithResponse:(NSURLResponse *)response
                     newRequest:(NSURLRequest *)redirectRequest
               redirectDecision:(EMASCurlNetRedirectDecisionCallback)redirectDecisionCallback
                  urlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask;

@end

@protocol EMASCurlResourceMatcherIteratorDataSource <NSObject>

- (NSArray<id<EMASCurlResourceMatcherImplProtocol>> *)liveResMatchers;

@end

API_AVAILABLE(ios(LimitVersion))
@interface EMASCurlResourceMatcherIterator : NSObject

@property (nonatomic, weak) id<EMASCurlResourceMatcherIteratorProtocol> iteratorDelagate;

@property (nonatomic, weak) id<EMASCurlResourceMatcherIteratorDataSource> iteratorDataSource;

- (void)startWithUrlSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask;

@end

NS_ASSUME_NONNULL_END
