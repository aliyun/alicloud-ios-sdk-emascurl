//
//  EMASCurlCacheConstants.h
//  EMASCurl
//
//  Created by xuyecan on 2025/5/12.
//

#ifndef EMASCurlCacheConstants_h
#define EMASCurlCacheConstants_h

// 请求相关的属性键
#define kEMASCurlCacheEnabled @"kEMASCurlCacheEnabled"
#define kEMASCurlForceRefreshKey @"kEMASCurlForceRefreshKey"

// 默认缓存容量 (50 MB)
#define kEMASCurlDefaultCacheCapacity (50 * 1024 * 1024)

// 标记用于收集响应数据
#define kEMASCurlResponseDataKey @"kEMASCurlResponseDataKey"

#define EMASHTTPHeaderCacheControl @"Cache-Control"
#define EMASHTTPHeaderPragma @"Pragma"
#define EMASHTTPHeaderExpires @"Expires"
#define EMASHTTPHeaderDate @"Date"
#define EMASHTTPHeaderETag @"Etag"
#define EMASHTTPHeaderLastModified @"Last-Modified"
#define EMASHTTPHeaderAge @"Age"
#define EMASHTTPHeaderVary @"Vary"

#define EMASCacheControlNoCache @"no-cache"
#define EMASCacheControlNoStore @"no-store"
#define EMASCacheControlMaxAge @"max-age"
#define EMASCacheControlSMaxAge @"s-maxage"
#define EMASCacheControlMustRevalidate @"must-revalidate"
#define EMASCacheControlPublic @"public"
#define EMASCacheControlPrivate @"private"

#define EMASUserInfoKeyStorageTimestamp @"EMASUserInfoKeyStorageTimestamp"
#define EMASUserInfoKeyOriginalDateHeader @"EMASUserInfoKeyOriginalDateHeader"
#define EMASUserInfoKeyOriginalExpiresHeader @"EMASUserInfoKeyOriginalExpiresHeader"
#define EMASUserInfoKeyOriginalHTTPVersion @"EMASUserInfoKeyOriginalHTTPVersion"
#define EMASUserInfoKeyOriginalStatusCode @"EMASUserInfoKeyOriginalStatusCode"

#endif /* EMASCurlCacheConstants_h */
