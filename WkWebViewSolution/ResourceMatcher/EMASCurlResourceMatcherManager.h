//
//  EMASCurlSchemeHandleManager.h

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import "EMASCurlCacheProtocol.h"
#import "EMASCurlUtils.h"

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(LimitVersion))
@protocol EMASCurlResourceMatcherManagerDelegate <NSObject>

- (NSArray<id<EMASCurlResourceMatcherImplProtocol>> *)liveMatchers;

- (void)redirectWithRequest:(NSURLRequest *)redirectRequest;

@end

API_AVAILABLE(ios(LimitVersion))
@interface EMASCurlResourceMatcherManager : NSObject

@property (nonatomic, weak) id<EMASCurlResourceMatcherManagerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
