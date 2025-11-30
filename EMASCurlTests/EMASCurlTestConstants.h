//
//  EMASCurlTestConstants.h
//  EMASCurlTests
//
//  Created by xuyecan on 2024/12/15.
//

#ifndef EMASCurlTestConstants_h
#define EMASCurlTestConstants_h

#import <Foundation/Foundation.h>

static NSString *HTTP11_ENDPOINT = @"http://127.0.0.1:9080";

static NSString *HTTP2_ENDPOINT = @"https://127.0.0.1:9443";

// Timeout test endpoint (server that delays TCP accept by 2 seconds)
static NSString *TIMEOUT_TEST_ENDPOINT = @"http://127.0.0.1:9081";

static NSString *PATH_ECHO = @"/echo";

static NSString *PATH_COOKIE_SET = @"/cookie/set";
static NSString *PATH_COOKIE_VERIFY = @"/cookie/verify";

static NSString *PATH_REDIRECT = @"/redirect";

static NSString *PATH_REDIRECT_CHAIN = @"/redirect_chain";

static NSString *PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED = @"/download/1MB_data_at_200KBps_speed";

static NSString *PATH_GZIP_RESPONSE = @"/get/gzip_response";
static NSString *PATH_CACHE_NO_STORE = @"/cache/no_store";
static NSString *PATH_CACHE_CACHEABLE = @"/cache/cacheable";
static NSString *PATH_CACHE_404 = @"/cache/404";
static NSString *PATH_CACHE_410 = @"/cache/410";

static NSString *PATH_UPLOAD_POST_SLOW = @"/upload/post/slow";

static NSString *PATH_UPLOAD_PUT_SLOW = @"/upload/put/slow";

static NSString *PATH_UPLOAD_PATCH_SLOW = @"/upload/patch/slow";

static NSString *PATH_UPLOAD_DELETE_SLOW = @"/upload/delete/slow";

static NSString *PATH_UPLOAD_POST_CHUNKED = @"/upload/post/chunked";

static NSString *PATH_TIMEOUT_REQUEST = @"/timeout/request";

// Redirect test paths
static NSString *PATH_REDIRECT_301 = @"/redirect/301";
static NSString *PATH_REDIRECT_307 = @"/redirect/307";
static NSString *PATH_REDIRECT_307_POST = @"/redirect/307/post";
static NSString *PATH_REDIRECT_SET_COOKIE = @"/redirect/set_cookie";
static NSString *PATH_REDIRECT_CACHEABLE = @"/redirect/cacheable";

// Slow response paths for cancellation testing
static NSString *PATH_SLOW_HEADERS = @"/slow/headers";
static NSString *PATH_SLOW_BODY = @"/slow/body";
static NSString *PATH_SLOW_LONG_BODY = @"/slow/long_body";

#endif /* EMASCurlTestConstants_h */
