//
//  EMASCurlProtocolEarlyFailTest.m
//
//  EMASCurl
//
//  @author Created by Claude Code on 2025/10/21
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <EMASCurl/EMASCurlProtocol.h>

// 为避免在测试目标中引入 libcurl 头文件，这里用占位声明匹配指针尺寸
// 复杂逻辑：仅用于 method swizzling 的签名对齐，不参与实际调用
typedef void CURL;

@interface EMASCurlProtocol (EMAS_EarlyFail_Swizzle)
- (void)emas_test_configEasyHandle:(CURL *)easyHandle error:(NSError **)error;
@end
@implementation EMASCurlProtocol (EMAS_EarlyFail_Swizzle)
- (void)emas_test_configEasyHandle:(CURL *)easyHandle error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:@"EMAS.TEST" code:-999 userInfo:@{NSLocalizedDescriptionKey: @"inject early fail"}];
    }
}
@end

@interface EMASCurlProtocolEarlyFailTest : XCTestCase
@end

@implementation EMASCurlProtocolEarlyFailTest

- (void)testStopLoadingDoesNotHangOnEarlyConfigFailure {
    // 复杂逻辑：通过 method swizzling 注入 configEasyHandle 的失败分支，验证 stopLoading 不会无限阻塞
    Method m1 = class_getInstanceMethod(EMASCurlProtocol.class, @selector(configEasyHandle:error:));
    Method m2 = class_getInstanceMethod(EMASCurlProtocol.class, @selector(emas_test_configEasyHandle:error:));
    method_exchangeImplementations(m1, m2);

    @try {
        NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9/"];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        [EMASCurlProtocol setConnectTimeoutIntervalForRequest:req connectTimeoutInterval:0.2];

        XCTestExpectation *didFail = [self expectationWithDescription:@"didFail callback"];

        __block BOOL finished = NO;
        id<NSURLProtocolClient> client = (id<NSURLProtocolClient>)[[NSObject alloc] init];

        // 动态代理仅拦截 didFailWithError
        class_addMethod([client class], @selector(URLProtocol:didFailWithError:), imp_implementationWithBlock(^(id _self, NSURLProtocol *p, NSError *e){ finished = YES; [didFail fulfill]; }), "v@:@@");

        EMASCurlProtocol *p = [[EMASCurlProtocol alloc] initWithRequest:req cachedResponse:nil client:client];
        [p startLoading];

        [self waitForExpectations:@[didFail] timeout:5.0];

        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        [p stopLoading];
        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - t0;

        XCTAssertTrue(elapsed < 1.0, @"stopLoading 应在早期失败时快速返回，elapsed=%.3f", elapsed);
        XCTAssertTrue(finished, @"应触发 didFail 回调");
    } @finally {
        method_exchangeImplementations(m1, m2);
    }
}

@end
