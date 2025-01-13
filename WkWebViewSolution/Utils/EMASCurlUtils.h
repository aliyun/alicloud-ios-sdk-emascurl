
#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

#define LimitVersion 13.0

#define xURLSchemeHandlerKey "xURLSchemeHandlerKey"

#define EMASCurlValidStr(str) [EMASCurlUtils isValidStr:str]
#define EMASCurlValidDic(dic) [EMASCurlUtils isValidDic:dic]
#define EMASCurlValidArr(arr) [EMASCurlUtils isValidArr:arr]
#define EMASCurlWeak(v) __weak typeof(v)weak##v = v;
#define EMASCurlStrong(v) __strong typeof(weak##v)v = weak##v;

//// log
FOUNDATION_EXPORT void EMASCurlCacheLog(NSString * _Nonnull format, ...) ;

@interface EMASCurlUtils : NSObject

+ (void)setLogEnable:(BOOL)enable ;

+ (BOOL)isValidStr:(NSString *)str;

+ (BOOL)isValidDic:(NSDictionary *)dic;

+ (BOOL)isValidArr:(NSArray *)arr;

+ (id)obj:(id)obj withPerformSel:(SEL)sel defaultValue:(nullable id)defaultValue;

+ (id)obj:(id)obj withPerformSel:(SEL)sel obj1:(nullable id)obj1 defaultValue:(nullable id)defaultValue;

+ (id)obj:(id)obj withPerformSel:(SEL)sel obj1:(nullable id)obj1 obj2:(nullable id)obj2 defaultValue:(nullable id)defaultValue;

+ (BOOL)isEqualURLA:(NSString *)urlStrA withURLB:(NSString *)urlStrB;

+ (long long)getAvailableMemorySize;

+ (long long)getTotalMemorySize;

+ (void)safeMainQueueBlock:(void (^)(void))block;

+ (NSDictionary *)dicWithJson:(id)json;

+ (NSArray *)arrayWithJson:(id)json;

+ (nullable id)objWithJson:(id)json;

+ (NSString *)objToJson:(id)obj;

+ (NSData *)dataWithBase64Decode:(NSString *)data;

+ (NSHTTPCookie *)cookieWithStr:(NSString *)str url:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
