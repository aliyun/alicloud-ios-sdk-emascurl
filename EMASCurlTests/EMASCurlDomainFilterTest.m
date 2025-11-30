//
//  EMASCurlDomainFilterTest.m
//
//  EMASCurl
//
//  @author Created by Claude Code on 2025/11/30
//

#import <XCTest/XCTest.h>
#import <EMASCurl/EMASCurlProtocol.h>

@interface EMASCurlDomainFilterTest : XCTestCase
@end

@implementation EMASCurlDomainFilterTest

- (void)setUp {
    [super setUp];
    // 每个测试前重置域名过滤配置
    [EMASCurlProtocol setHijackDomainWhiteList:nil];
    [EMASCurlProtocol setHijackDomainBlackList:nil];
}

- (void)tearDown {
    // 测试后清理配置
    [EMASCurlProtocol setHijackDomainWhiteList:nil];
    [EMASCurlProtocol setHijackDomainBlackList:nil];
    [super tearDown];
}

#pragma mark - Whitelist Tests

- (void)testWhitelistOnlyInterceptsListedDomains {
    // 设置白名单：仅拦截 example.com 和 test.com
    [EMASCurlProtocol setHijackDomainWhiteList:@[@"example.com", @"test.com"]];

    // 白名单内的域名应被拦截
    NSURLRequest *allowedRequest1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/path"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:allowedRequest1], @"白名单内的域名应被拦截");

    NSURLRequest *allowedRequest2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://api.example.com/path"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:allowedRequest2], @"白名单子域名应被拦截 (hasSuffix)");

    NSURLRequest *allowedRequest3 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://test.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:allowedRequest3], @"白名单内的第二个域名应被拦截");

    // 白名单外的域名不应被拦截
    NSURLRequest *rejectedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.com/path"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:rejectedRequest], @"白名单外的域名不应被拦截");
}

- (void)testEmptyWhitelistInterceptsAllDomains {
    // 空白名单不应影响拦截行为（相当于未设置白名单）
    [EMASCurlProtocol setHijackDomainWhiteList:@[]];

    NSURLRequest *request1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:request1], @"空白名单时所有域名应被拦截");

    NSURLRequest *request2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:request2], @"空白名单时所有域名应被拦截");
}

- (void)testNilWhitelistInterceptsAllDomains {
    // nil白名单不应影响拦截行为
    [EMASCurlProtocol setHijackDomainWhiteList:nil];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://anywebsite.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:request], @"nil白名单时所有域名应被拦截");
}

#pragma mark - Blacklist Tests

- (void)testBlacklistBypassesListedDomains {
    // 设置黑名单：跳过 blocked.com
    [EMASCurlProtocol setHijackDomainBlackList:@[@"blocked.com"]];

    // 黑名单内的域名不应被拦截
    NSURLRequest *blockedRequest1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://blocked.com/path"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:blockedRequest1], @"黑名单内的域名不应被拦截");

    NSURLRequest *blockedRequest2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://api.blocked.com/"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:blockedRequest2], @"黑名单子域名不应被拦截 (hasSuffix)");

    // 黑名单外的域名应被拦截
    NSURLRequest *allowedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://allowed.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:allowedRequest], @"黑名单外的域名应被拦截");
}

- (void)testEmptyBlacklistDoesNotBlockAnyDomain {
    // 空黑名单不应阻止任何域名
    [EMASCurlProtocol setHijackDomainBlackList:@[]];

    NSURLRequest *request1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:request1], @"空黑名单不应阻止任何域名");

    NSURLRequest *request2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:request2], @"空黑名单不应阻止任何域名");
}

#pragma mark - Whitelist + Blacklist Combination Tests

- (void)testBlacklistTakesPrecedenceOverWhitelist {
    // 同时设置黑名单和白名单，黑名单优先
    [EMASCurlProtocol setHijackDomainWhiteList:@[@"example.com"]];
    [EMASCurlProtocol setHijackDomainBlackList:@[@"api.example.com"]];

    // 子域名在黑名单中，即使匹配白名单也不应被拦截
    NSURLRequest *blockedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://api.example.com/path"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:blockedRequest], @"黑名单应优先于白名单");

    // 主域名在白名单中但不在黑名单中，应被拦截
    NSURLRequest *allowedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.example.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:allowedRequest], @"白名单域名不在黑名单中应被拦截");

    // 既不在白名单也不在黑名单中，不应被拦截（因为设置了白名单）
    NSURLRequest *rejectedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.com/"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:rejectedRequest], @"不在白名单中的域名不应被拦截");
}

#pragma mark - Edge Cases

- (void)testDomainMatchingWithSuffix {
    // 测试域名后缀匹配逻辑
    // 注意：当前实现使用 hasSuffix，所以 notexample.com 也会匹配 example.com
    [EMASCurlProtocol setHijackDomainWhiteList:@[@"example.com"]];

    // 完全匹配
    NSURLRequest *exactMatch = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:exactMatch], @"完全匹配域名应被拦截");

    // 子域名匹配
    NSURLRequest *subdomainMatch = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://sub.example.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:subdomainMatch], @"子域名应匹配 (hasSuffix)");

    // 多级子域名匹配
    NSURLRequest *deepSubdomain = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://a.b.c.example.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:deepSubdomain], @"多级子域名应匹配");

    // 注意：当前实现的 hasSuffix 会把 notexample.com 也匹配上 example.com
    // 这是一个已知的行为限制，实际使用时应在白名单中使用 .example.com 的形式
    NSURLRequest *notSuffix = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://notexample.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:notSuffix], @"hasSuffix 会匹配 notexample.com");
}

- (void)testHTTPSchemeIsIntercepted {
    // 验证 HTTP 协议也能被拦截
    NSURLRequest *httpRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://example.com/"]];
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:httpRequest], @"HTTP 请求应被拦截");
}

- (void)testNonHTTPSchemeIsNotIntercepted {
    // 验证非 HTTP/HTTPS 协议不被拦截
    NSURLRequest *ftpRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"ftp://example.com/"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:ftpRequest], @"FTP 请求不应被拦截");

    NSURLRequest *fileRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"file:///path/to/file"]];
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:fileRequest], @"file:// 请求不应被拦截");
}

- (void)testMultipleDomainsInWhitelist {
    // 测试白名单中多个域名
    [EMASCurlProtocol setHijackDomainWhiteList:@[@"a.com", @"b.com", @"c.com"]];

    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://a.com/"]];
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://b.com/"]];
    NSURLRequest *req3 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://c.com/"]];
    NSURLRequest *req4 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://d.com/"]];

    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req1], @"白名单域名 a.com 应被拦截");
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req2], @"白名单域名 b.com 应被拦截");
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req3], @"白名单域名 c.com 应被拦截");
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req4], @"非白名单域名 d.com 不应被拦截");
}

- (void)testMultipleDomainsInBlacklist {
    // 测试黑名单中多个域名
    [EMASCurlProtocol setHijackDomainBlackList:@[@"x.com", @"y.com"]];

    NSURLRequest *req1 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/"]];
    NSURLRequest *req2 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://y.com/"]];
    NSURLRequest *req3 = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://z.com/"]];

    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req1], @"黑名单域名 x.com 不应被拦截");
    XCTAssertFalse([EMASCurlProtocol canInitWithRequest:req2], @"黑名单域名 y.com 不应被拦截");
    XCTAssertTrue([EMASCurlProtocol canInitWithRequest:req3], @"非黑名单域名 z.com 应被拦截");
}

@end
