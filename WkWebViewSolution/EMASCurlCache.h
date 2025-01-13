//
//  EMASCurlCache.h

#import "EMASCurlCacheProtocol.h"
#import "EMASCurlCacheLoader.h"
#import "EMASCurlNetworkManager.h"
#import "WKWebViewConfiguration+Loader.h"
#import "EMASCurlUtils.h"
#import "EMASCurlSafeArray.h"
#import "EMASCurlSafeDictionary.h"


NS_ASSUME_NONNULL_BEGIN

@interface EMASCurlCache : NSObject

+ (EMASCurlCache *)shareInstance;

@property (nonatomic, strong) id <EMASCurlURLCacheDelegate> netCache; // 网络数据缓存

@property (nonatomic, assign) BOOL LogEnabled; // log开关

@end

NS_ASSUME_NONNULL_END
