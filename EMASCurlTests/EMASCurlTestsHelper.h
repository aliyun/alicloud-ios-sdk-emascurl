#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCTestCase (EMASCurlTestsHelper)

- (NSString *)pathForTestResource:(NSString *)name ofType:(NSString *)ext;
- (NSData *)dataFromTestResource:(NSString *)name ofType:(NSString *)ext;

@end

NS_ASSUME_NONNULL_END
