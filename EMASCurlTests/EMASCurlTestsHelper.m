#import "EMASCurlTestsHelper.h"

@implementation XCTestCase (EMASCurlTestsHelper)

- (NSString *)pathForTestResource:(NSString *)name ofType:(NSString *)ext {
    NSBundle *testBundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [testBundle pathForResource:name ofType:ext];
    XCTAssertNotNil(path, @"Resource %@.%@ not found in test bundle", name, ext);
    return path;
}

- (NSData *)dataFromTestResource:(NSString *)name ofType:(NSString *)ext {
    NSString *path = [self pathForTestResource:name ofType:ext];
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"Failed to read data from %@.%@", name, ext);
    return data;
}

@end
