//
//  EMASCurlUtils.h
//  EMASCurl
//
//  Created by xuyecan on 2025/5/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 字符串是否有效（非nil且长度大于0）
static inline BOOL EMASCurlValidStr(NSString * _Nullable str) {
    return (str && [str isKindOfClass:[NSString class]] && str.length > 0);
}

NS_ASSUME_NONNULL_END
