//
//  EMASCurlPathFilterTest.m
//
//  EMASCurl
//
//  @author Created by Claude Code on 2025/12/08
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurlProtocol.h>

@interface EMASCurlPathFilterTest : XCTestCase
@end

@implementation EMASCurlPathFilterTest

- (void)setUp {
    [super setUp];
    // 每个测试前重置配置
    [EMASCurlProtocol setHijackDomainWhiteList:nil];
    [EMASCurlProtocol setHijackDomainBlackList:nil];
    [EMASCurlProtocol setHijackUrlPathBlackList:nil];
}

- (void)tearDown {
    // 测试后清理配置
    [EMASCurlProtocol setHijackDomainWhiteList:nil];
    [EMASCurlProtocol setHijackDomainBlackList:nil];
    [EMASCurlProtocol setHijackUrlPathBlackList:nil];
    [super tearDown];
}

#pragma mark - Exact Match Tests

- (void)testExactPathMatch {
    // 设置精确路径黑名单
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/api/blocked.do"]];

    // 精确匹配的路径不应被拦截
    NSURLRequest *blockedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/blocked.do"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:blockedRequest], @"精确匹配的路径不应被拦截");

    // 不匹配的路径应被拦截
    NSURLRequest *allowedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/allowed.do"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:allowedRequest], @"不匹配的路径应被拦截");

    // 子路径不应匹配
    NSURLRequest *subpathRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/blocked.do/extra"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:subpathRequest], @"子路径不应匹配精确模式");
}

#pragma mark - Single Wildcard Tests

- (void)testSingleWildcardMatchesOneSegment {
    // 设置单级通配符黑名单
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/api/*"]];

    // /api/foo 应匹配
    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/foo"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req1], @"/api/* 应匹配 /api/foo");

    // /api/bar 应匹配
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/bar"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req2], @"/api/* 应匹配 /api/bar");

    // /api/ 应匹配（空段）
    NSURLRequest *req3 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req3], @"/api/* 应匹配 /api/（空段）");

    // /api 应匹配（无尾斜杠）
    NSURLRequest *req4 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req4], @"/api/* 应匹配 /api（无尾斜杠）");
}

- (void)testSingleWildcardDoesNotMatchMultipleSegments {
    // 设置单级通配符黑名单
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/api/*"]];

    // /api/foo/bar 不应匹配（多级）
    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/foo/bar"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req1], @"/api/* 不应匹配 /api/foo/bar（多级）");

    // /api/a/b/c 不应匹配
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/a/b/c"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req2], @"/api/* 不应匹配 /api/a/b/c");
}

#pragma mark - Multi Wildcard Tests

- (void)testMultiWildcardMatchesPrefix {
    // 设置多级通配符黑名单
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/admin/**"]];

    // /admin 应匹配（前缀本身）
    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/admin"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req1], @"/admin/** 应匹配 /admin");

    // /admin/ 应匹配
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/admin/"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req2], @"/admin/** 应匹配 /admin/");

    // /admin/users 应匹配
    NSURLRequest *req3 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/admin/users"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req3], @"/admin/** 应匹配 /admin/users");
}

- (void)testMultiWildcardMatchesAllDepths {
    // 设置多级通配符黑名单
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/admin/**"]];

    // /admin/a/b 应匹配
    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/admin/a/b"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req1], @"/admin/** 应匹配 /admin/a/b");

    // /admin/x/y/z 应匹配
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/admin/x/y/z"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req2], @"/admin/** 应匹配 /admin/x/y/z");

    // /admin/deep/nested/path/here 应匹配
    NSURLRequest *req3 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/admin/deep/nested/path/here"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req3], @"/admin/** 应匹配深层嵌套路径");
}

- (void)testMultiWildcardDoesNotMatchOtherPaths {
    // 设置多级通配符黑名单
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/admin/**"]];

    // /administrator 不应匹配（不同前缀）
    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/administrator"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req1], @"/admin/** 不应匹配 /administrator");

    // /api/admin 不应匹配
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/admin"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req2], @"/admin/** 不应匹配 /api/admin");
}

#pragma mark - Empty/Nil Blacklist Tests

- (void)testNilPathBlacklistAllowsAll {
    // nil路径黑名单不应阻止任何请求
    [EMASCurlProtocol setHijackUrlPathBlackList:nil];

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/any/path"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req], @"nil路径黑名单不应阻止请求");
}

- (void)testEmptyPathBlacklistAllowsAll {
    // 空路径黑名单不应阻止任何请求
    [EMASCurlProtocol setHijackUrlPathBlackList:@[]];

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/any/path"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req], @"空路径黑名单不应阻止请求");
}

#pragma mark - Domain Whitelist + Path Blacklist Combination Tests

- (void)testPathBlacklistWorksWithDomainWhitelist {
    // 设置域名白名单和路径黑名单
    [EMASCurlProtocol setHijackDomainWhiteList:@[@"example.com"]];
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/blocked/**"]];

    // 白名单域名 + 非黑名单路径 = 应拦截
    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/allowed/path"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req1], @"白名单域名 + 非黑名单路径应被拦截");

    // 白名单域名 + 黑名单路径 = 不应拦截
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/blocked/path"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req2], @"白名单域名 + 黑名单路径不应被拦截");

    // 非白名单域名 = 不应拦截（域名白名单优先）
    NSURLRequest *req3 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.com/allowed/path"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req3], @"非白名单域名不应被拦截");
}

- (void)testDomainBlacklistTakesPrecedenceOverPathBlacklist {
    // 设置域名黑名单和路径黑名单
    [EMASCurlProtocol setHijackDomainBlackList:@[@"blocked.com"]];
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/allowed/path"]];

    // 域名黑名单域名 = 不应拦截（域名黑名单优先）
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://blocked.com/some/path"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req], @"域名黑名单应优先于路径黑名单");
}

#pragma mark - Multiple Patterns Tests

- (void)testMultiplePathPatterns {
    // 设置多个路径模式
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/exact/path", @"/single/*", @"/multi/**"]];

    // 精确匹配
    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/exact/path"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req1], @"精确路径应被阻止");

    // 单级通配符
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/single/item"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req2], @"单级通配符应被阻止");

    // 多级通配符
    NSURLRequest *req3 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/multi/a/b/c"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req3], @"多级通配符应被阻止");

    // 不匹配任何模式
    NSURLRequest *req4 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/other/path"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req4], @"不匹配任何模式的路径应被拦截");
}

#pragma mark - Edge Cases

- (void)testRootPath {
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/"]];

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req], @"根路径应被阻止");
}

- (void)testPathWithQueryString {
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/api/blocked"]];

    // URL.path 不包含查询字符串
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/blocked?query=1"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req], @"带查询字符串的路径应匹配（path不含query）");
}

- (void)testPathWithFragment {
    [EMASCurlProtocol setHijackUrlPathBlackList:@[@"/api/blocked"]];

    // URL.path 不包含片段
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/api/blocked#section"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req], @"带片段的路径应匹配（path不含fragment）");
}

@end
