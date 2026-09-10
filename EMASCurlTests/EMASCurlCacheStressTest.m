#import <XCTest/XCTest.h>
#import "EMASCurlCacheStressScenario.h"

@interface EMASCurlCacheStressTest : XCTestCase
@end

@implementation EMASCurlCacheStressTest
- (void)runScenarioUpdating304:(BOOL)update304 {
    NSInteger iterations = [NSProcessInfo.processInfo.environment[@"EMASCURL_CACHE_STRESS_ITERATIONS"] integerValue];
    XCTSkipIf(iterations <= 0, @"手工启用压力验证：设置 EMASCURL_CACHE_STRESS_ITERATIONS；默认 CI 不运行");
    XCTAssertLessThanOrEqual(iterations, 1000000, @"限制单轮工作量");
    if (iterations > 1000000) return;
    NSDictionary *result = EMASRunCacheStress((NSUInteger)iterations, update304);
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
    NSLog(@"CACHE_STRESS_RESULT %@", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
    XCTAssertTrue([result[@"passed"] boolValue], @"压力场景出现缓存未命中、回调缺失或内容不一致：%@", result);
}
- (void)testTwoReadersWithCallbackHandoff { [self runScenarioUpdating304:NO]; }
- (void)test304UpdatesWithTwoReadersAndCallbackHandoff { [self runScenarioUpdating304:YES]; }
@end
