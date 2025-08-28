//
//  EMASLocalProxyTestConstants.h
//  EMASLocalProxyTests
//
//  Created by xuyecan on 2025/08/25.
//

#ifndef EMASLocalProxyTestConstants_h
#define EMASLocalProxyTestConstants_h

#import <Foundation/Foundation.h>

// EMASLocalProxy 测试端点 - 区分 HTTP vs HTTPS 连接模式
static NSString *HTTP_ENDPOINT = @"http://127.0.0.1:9080";   // Plain HTTP - 直连模式

static NSString *HTTPS_ENDPOINT = @"https://127.0.0.1:9443"; // HTTPS - CONNECT隧道模式

// Timeout test endpoint (server that delays TCP accept by 2 seconds)
static NSString *TIMEOUT_TEST_ENDPOINT = @"http://127.0.0.1:9081";

static NSString *PATH_ECHO = @"/echo";

static NSString *PATH_COOKIE_SET = @"/cookie/set";
static NSString *PATH_COOKIE_VERIFY = @"/cookie/verify";

static NSString *PATH_REDIRECT = @"/redirect";

static NSString *PATH_REDIRECT_CHAIN = @"/redirect_chain";

static NSString *PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED = @"/download/1MB_data_at_200KBps_speed";

static NSString *PATH_GZIP_RESPONSE = @"/get/gzip_response";

static NSString *PATH_UPLOAD_POST_SLOW = @"/upload/post/slow";

static NSString *PATH_UPLOAD_PUT_SLOW = @"/upload/put/slow";

static NSString *PATH_UPLOAD_POST_SLOW_403 = @"/upload/post/slow_403";

static NSString *PATH_UPLOAD_PUT_SLOW_403 = @"/upload/put/slow_403";

static NSString *PATH_UPLOAD_POST_IMMEDIATE_403 = @"/upload/post/immediate_403";

static NSString *PATH_UPLOAD_PUT_IMMEDIATE_403 = @"/upload/put/immediate_403";

static NSString *PATH_TIMEOUT_REQUEST = @"/timeout/request";

static NSString *PATH_HALF_CLOSE_TEST = @"/half_close_test";

static NSString *PATH_STREAM = @"/stream";

// 连接复用测试相关路径
static NSString *PATH_CONNECTION_ID = @"/connection_id";
static NSString *PATH_KEEP_ALIVE_TEST = @"/keep_alive_test";
static NSString *PATH_CONNECTION_CLOSE_TEST = @"/connection_close_test";
static NSString *PATH_PIPELINE_TEST = @"/pipeline_test";
static NSString *PATH_CONNECTION_STATS = @"/connection_stats";

#endif /* EMASLocalProxyTestConstants_h */
