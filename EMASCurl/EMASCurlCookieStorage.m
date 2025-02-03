//
//  EMASCurlCookieStorage.m
//  EMASCurl
//
//  Created by xuyecan on 2025/2/3.
//

#import "EMASCurlCookieStorage.h"

static NSString *const kEMASCurlCookieStorageKey = @"EMASCurlCookieStorage";
static NSTimeInterval const kPersistenceInterval = 15.0;

@interface EMASCurlCookieStorage ()
@property (nonatomic, strong) dispatch_queue_t persistQueue;
@property (nonatomic, strong) dispatch_source_t persistTimer;
@end

@implementation EMASCurlCookieStorage

+ (instancetype)sharedStorage {
    static EMASCurlCookieStorage *sharedStorage = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedStorage = [[self alloc] init];
    });
    return sharedStorage;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 创建用于做持久化操作的队列
        _persistQueue = dispatch_queue_create("com.alicloud.emascurl.cookiestorage.persist", DISPATCH_QUEUE_SERIAL);

        // 从本地加载 cookies
        [self loadPersistedCookies];

        // 设置定时器进行持久化
        [self setupPersistenceTimer];
    }
    return self;
}

- (void)dealloc {
    if (_persistTimer) {
        dispatch_source_cancel(_persistTimer);
    }
}

#pragma mark - Public Methods

- (void)setCookieWithString:(NSString *)cookieString forURL:(NSURL *)url {
    if (!cookieString.length || !url) {
        return;
    }

    // 解析 Set-Cookie 字符串并设置到 NSHTTPCookieStorage
    NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:@{@"Set-Cookie": cookieString} forURL:url];
    [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies:cookies forURL:url mainDocumentURL:nil];
}

- (NSString *)cookieStringForURL:(NSURL *)url {
    if (!url) {
        return nil;
    }

    NSArray<NSHTTPCookie *> *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url];
    NSDictionary *headers = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
    return headers[@"Cookie"];
}

#pragma mark - Private Methods

- (void)setupPersistenceTimer {
    self.persistTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.persistQueue);
    dispatch_source_set_timer(self.persistTimer,
                            dispatch_time(DISPATCH_TIME_NOW, kPersistenceInterval * NSEC_PER_SEC),
                            kPersistenceInterval * NSEC_PER_SEC,
                            1 * NSEC_PER_SEC);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.persistTimer, ^{
        [weakSelf persistCookies];
    });

    dispatch_resume(self.persistTimer);
}

- (void)loadPersistedCookies {
    dispatch_async(self.persistQueue, ^{
        NSArray *cookiesData = [[NSUserDefaults standardUserDefaults] objectForKey:kEMASCurlCookieStorageKey];
        if (!cookiesData) {
            return;
        }

        NSArray<NSHTTPCookie *> *cookies = [self deserializeCookies:cookiesData];
        for (NSHTTPCookie *cookie in cookies) {
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
        }
    });
}

- (void)persistCookies {
    NSArray<NSHTTPCookie *> *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
    NSArray *serializedCookies = [self serializeCookies:cookies];

    [[NSUserDefaults standardUserDefaults] setObject:serializedCookies forKey:kEMASCurlCookieStorageKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSArray *)serializeCookies:(NSArray<NSHTTPCookie *> *)cookies {
    NSMutableArray *serializedCookies = [NSMutableArray array];

    for (NSHTTPCookie *cookie in cookies) {
        if ([self isCookieValid:cookie]) {
            NSDictionary *cookieProperties = [self serializableCookieProperties:cookie];
            if (cookieProperties) {
                [serializedCookies addObject:cookieProperties];
            }
        }
    }

    return [serializedCookies copy];
}

- (NSArray<NSHTTPCookie *> *)deserializeCookies:(NSArray *)serializedCookies {
    NSMutableArray<NSHTTPCookie *> *cookies = [NSMutableArray array];

    for (NSDictionary *properties in serializedCookies) {
        NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:properties];
        if (cookie && [self isCookieValid:cookie]) {
            [cookies addObject:cookie];
        }
    }

    return [cookies copy];
}

- (BOOL)isCookieValid:(NSHTTPCookie *)cookie {
    NSDate *expiresDate = cookie.expiresDate;
    if (!expiresDate) {
        return YES;
    }
    return [expiresDate compare:[NSDate date]] == NSOrderedDescending;
}

- (NSDictionary *)serializableCookieProperties:(NSHTTPCookie *)cookie {
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];

    properties[NSHTTPCookieName] = cookie.name;
    properties[NSHTTPCookieValue] = cookie.value;
    properties[NSHTTPCookieDomain] = cookie.domain;
    properties[NSHTTPCookiePath] = cookie.path;

    if (cookie.secure) {
        properties[NSHTTPCookieSecure] = @YES;
    }

    if (cookie.expiresDate) {
        properties[NSHTTPCookieExpires] = cookie.expiresDate;
    }

    return [properties copy];
}

@end
