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


static NSString *PATH_ECHO = @"/echo";

static NSString *PATH_REDIRECT = @"/redirect";

static NSString *PATH_REDIRECT_CHAIN = @"/redirect_chain";

static NSString *PATH_DOWNLOAD_1MB_DATA_AT_200KBPS_SPEED = @"/download/1MB_data_at_200KBps_speed";

static NSString *PATH_GZIP_RESPONSE = @"/get/gzip_response";

static NSString *PATH_UPLOAD_SLOW = @"/upload/slow";


#endif /* EMASCurlTestConstants_h */
