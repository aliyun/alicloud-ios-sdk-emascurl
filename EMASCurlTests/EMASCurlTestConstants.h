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

static NSString *PATH_UPLOAD_POST_SLOW = @"/upload/post/slow";

static NSString *PATH_UPLOAD_PUT_SLOW = @"/upload/put/slow";

static NSString *PATH_TIMEOUT_REQUEST = @"/timeout/request";

#endif /* EMASCurlTestConstants_h */
