//
//  EMASLocalHttpProxy.m
//  iOS Local HTTP Proxy Solution
//
//  EMAS本地HTTP代理服务实现
//  支持多种客户端类型：WKWebView、NSURLSession等
//  提供透明代理支持，集成自定义DNS解析服务
//
//  主要功能：
//  • 自动启动本地HTTP代理服务
//  • 无缝集成自定义DNS解析服务（如HTTPDNS）
//  • WKWebView代理配置支持（需要iOS 17.0+）
//  • NSURLSession代理配置支持（支持iOS 17.0+）
//
//  Created by Alibaba Cloud EMAS Team on 2025/06/28.
//

#import "EMASLocalHttpProxy.h"

#pragma mark - 常量定义

/// 代理服务端口范围最小值
static const uint16_t kEMASLocalProxyPortMin = 31000;

/// 代理服务端口范围最大值
static const uint16_t kEMASLocalProxyPortMax = 32000;

/// 端口重试最大次数
static const NSInteger kEMASLocalProxyMaxRetryAttempts = 3;

/// 代理启动超时时间（秒）
static const NSTimeInterval kEMASLocalProxyStartupTimeout = 5.0;

/// 端口重试间隔时间（微秒）
static const useconds_t kEMASLocalProxyRetryInterval = 100000; // 100ms

/// 自定义WebView数据存储标识符
static NSString * const kEMASLocalProxyDataStoreUUID = @"CE5A8E48-C35B-4690-8526-D851C7B9A36B";

/// 当前日志级别配置
static EMASLocalHttpProxyLogLevel _currentLogLevel = EMASLocalHttpProxyLogLevelDebug;

/// 检查是否应该输出指定级别的日志
static BOOL _shouldLog(EMASLocalHttpProxyLogLevel level) {
    return _currentLogLevel >= level;
}

/// 便捷日志宏定义（使用NSLog输出）
#define EMAS_LOCAL_HTTP_PROXY_LOG_INFO(fmt, ...)    do { \
    if (_shouldLog(EMASLocalHttpProxyLogLevelInfo)) { \
        NSLog(@"[LOCAL-PROXY-INFO] " fmt, ##__VA_ARGS__); \
    } \
} while(0)

#define EMAS_LOCAL_HTTP_PROXY_LOG_ERROR(fmt, ...)   do { \
    if (_shouldLog(EMASLocalHttpProxyLogLevelError)) { \
        NSLog(@"[LOCAL-PROXY-ERROR] " fmt, ##__VA_ARGS__); \
    } \
} while(0)

#define EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG(fmt, ...)   do { \
    if (_shouldLog(EMASLocalHttpProxyLogLevelDebug)) { \
        NSLog(@"[LOCAL-PROXY-DEBUG] " fmt, ##__VA_ARGS__); \
    } \
} while(0)

@interface EMASLocalHttpProxy ()

#pragma mark - 私有属性

/// 代理服务就绪状态（线程安全的原子操作属性）
@property (atomic, assign) BOOL isProxyReady;

/// 当前代理服务监听端口
@property (nonatomic, readonly) uint16_t proxyPort;

/// 自定义DNS解析器回调块
@property (nonatomic, copy) NSArray<NSString *> *(^customDNSResolverBlock)(NSString *hostname);

/// IP失败追踪字典，格式: {hostname: {ip: lastFailureTime}}
@property (atomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSDate *> *> *failedIPsPerHost;

#pragma mark - 私有方法

/// 数据中继辅助方法，避免递归调用
- (void)scheduleNextReceiveFrom:(nw_connection_t)source to:(nw_connection_t)destination onQueue:(dispatch_queue_t)queue;

@end

// iOS 17+ Proxy Configuration Support
// https://developer.apple.com/documentation/foundation/nsurlsessionconfiguration/proxyconfigurations?language=objc
API_AVAILABLE(ios(17.0))
@interface NSURLSessionConfiguration (ProxyConfigurations)

@property (copy) NSArray<NSObject<OS_nw_proxy_config> *> *proxyConfigurations;

@end

@implementation EMASLocalHttpProxy {
    /// 本地代理端口的监听器，负责接收客户端连接
    nw_listener_t _listener;

    /// 串行队列，用于同步start/stop操作，保证线程安全
    dispatch_queue_t _operationQueue;

    /// 串行队列，用于IP失败追踪的线程安全操作
    dispatch_queue_t _ipTrackingQueue;
}

#pragma mark - 初始化

+ (void)load {
    // 自动启动本地HTTPS代理服务，支持多种网络客户端集成
    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Preparing to start local HTTPS proxy service for network client integration");
    
    // 记录启动开始时间
    NSTimeInterval startTime = CACurrentMediaTime();
    
    // 异步启动代理服务
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        BOOL startupSuccess = [[self sharedInstance] start];

        // 计算启动耗时
        NSTimeInterval elapsedTime = (CACurrentMediaTime() - startTime) * 1000; // 转换为毫秒
        
        if (startupSuccess) {
            EMAS_LOCAL_HTTP_PROXY_LOG_INFO("Local HTTPS proxy service auto-start successful - elapsed time: %.2f ms", elapsedTime);
        } else {
            EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("Local HTTPS proxy service auto-start failed - elapsed time: %.2f ms", elapsedTime);
        }
    });
}

#pragma mark - 单例模式

+ (instancetype)sharedInstance {
    static EMASLocalHttpProxy *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[EMASLocalHttpProxy alloc] init];
    });
    return sharedInstance;
}

#pragma mark - 对象生命周期

- (instancetype)init {
    self = [super init];
    if (self) {
        // 初始化实例变量
        _proxyPort = 0;                    // 端口将在启动时动态分配
        _isProxyReady = NO;              // 初始状态为未运行
        _listener = NULL;                  // 监听器初始为空

        // 创建专用的串行队列用于同步start/stop操作
        _operationQueue = dispatch_queue_create("com.alicloud.httpdns.proxy.operation", DISPATCH_QUEUE_SERIAL);

        // 初始化IP失败追踪系统
        _failedIPsPerHost = [NSMutableDictionary dictionary];
        _ipTrackingQueue = dispatch_queue_create("com.alicloud.httpdns.iptracking", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stop];
    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Proxy service instance destroyed");
}

#pragma mark - 服务控制

#pragma mark - Helper Methods

/**
 *  创建指定端口的网络监听器
 *  @return 网络监听器，创建失败返回nil
 */
- (nw_listener_t)createListenerForPort:(uint16_t)port {
    // 配置网络连接参数
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL,    // 禁用TLS，代理本身不加密
        NW_PARAMETERS_DEFAULT_CONFIGURATION
    );

    // 启用地址重用，便于快速重启和端口复用
    nw_parameters_set_reuse_local_address(parameters, true);

    // 创建本地回环地址端点，仅监听本地连接
    NSString *portString = [NSString stringWithFormat:@"%d", port];
    nw_endpoint_t localEndpoint = nw_endpoint_create_host("127.0.0.1", [portString UTF8String]);
    nw_parameters_set_local_endpoint(parameters, localEndpoint);

    // 使用配置创建网络监听器
    nw_listener_t listener = nw_listener_create(parameters);

    if (!listener) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Port %d listener creation failed", port);
    }

    return listener;
}

/**
 *  记录监听器错误信息
 */
- (void)logListenerError:(nw_error_t)error context:(NSString *)context {
    if (error) {
        nw_error_domain_t domain = nw_error_get_error_domain(error);
        int code = nw_error_get_error_code(error);
        EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("%@ - error domain: %d, code: %d", context, domain, code);
    } else {
        EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("%@", context);
    }
}

/**
 *  等待监听器启动完成
 *  @return 启动是否成功
 */
- (BOOL)waitForListenerReady:(nw_listener_t)listener port:(uint16_t)port {
    __block BOOL startSuccess = NO;
    __block BOOL startCompleted = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    // 设置启动阶段状态处理器
    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t error) {
        if (startCompleted) return;

        switch (state) {
            case nw_listener_state_ready:
                self->_isProxyReady = YES;
                startSuccess = YES;
                startCompleted = YES;
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Port %d listener started successfully", port);
                dispatch_semaphore_signal(semaphore);
                break;

            case nw_listener_state_failed:
            case nw_listener_state_cancelled:
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Port %d listener startup failed - state: %d", port, state);
                if (error) {
                    [self logListenerError:error context:[NSString stringWithFormat:@"Port %d startup failed", port]];
                }
                startSuccess = NO;
                startCompleted = YES;
                dispatch_semaphore_signal(semaphore);
                break;

            default:
                break;
        }
    });

    // 配置连接处理器
    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
        EMAS_LOCAL_HTTP_PROXY_LOG_INFO("Incoming connection received at listener - connection: %p", connection);
        nw_connection_set_queue(connection, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        nw_connection_start(connection);
        [self handleConnection:connection];
    });

    // 启动监听器
    nw_listener_set_queue(listener, dispatch_get_main_queue());
    nw_listener_start(listener);

    // 等待启动完成（超时保护）
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kEMASLocalProxyStartupTimeout * NSEC_PER_SEC));
    long semaphoreResult = dispatch_semaphore_wait(semaphore, timeout);

    if (semaphoreResult != 0) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Port %d startup timeout (%.1f seconds)", port, kEMASLocalProxyStartupTimeout);
        return NO;
    }

    return startSuccess;
}

/**
 *  设置运行时状态监控
 *  监控代理服务运行期间的异常情况
 */
- (void)setupRuntimeStateMonitoring {
    if (!_listener) return;

    nw_listener_set_state_changed_handler(_listener, ^(nw_listener_state_t state, nw_error_t error) {
        switch (state) {
            case nw_listener_state_failed:
                EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("Proxy service runtime exception - listener failed");
                self->_isProxyReady = NO;
                [self logListenerError:error context:@"Proxy service runtime exception"];
                break;

            case nw_listener_state_cancelled:
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Proxy service listener cancelled");
                self->_isProxyReady = NO;
                break;

            default:
                break;
        }
    });
}

/**
 *  尝试在指定端口启动代理服务
 */
- (BOOL)tryStartOnPort:(uint16_t)port {
    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Attempting to start on port: 127.0.0.1:%d", port);

    _listener = [self createListenerForPort:port];
    if (!_listener) {
        return NO;
    }

    BOOL success = [self waitForListenerReady:_listener port:port];

    if (success) {
        [self setupRuntimeStateMonitoring];
        EMAS_LOCAL_HTTP_PROXY_LOG_INFO("Proxy service started successfully - listening address: 127.0.0.1:%d", port);
    }

    return success;
}

/**
 *  自动选择可用端口并启动本地HTTPS代理服务
 *  支持端口冲突重试机制，最多尝试3个随机端口
 */
- (BOOL)start {
    __block BOOL result = NO;

    dispatch_sync(_operationQueue, ^{
        // 检查服务是否已经在运行
        if (self.isProxyReady) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Proxy service already running - listening address: 127.0.0.1:%d", _proxyPort);
            result = YES;
            return;
        }

        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Starting proxy service");

        // 端口重试机制：最多尝试指定次数的随机端口
        for (NSInteger attempt = 0; attempt < kEMASLocalProxyMaxRetryAttempts; attempt++) {
            uint16_t port = [self generateRandomPort];

            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Attempt %ld/%ld to start - port: 127.0.0.1:%d",
                            (long)(attempt + 1), (long)kEMASLocalProxyMaxRetryAttempts, port);

            // 尝试在指定端口启动服务
            if ([self tryStartOnPort:port]) {
                _proxyPort = port;
                result = YES;
                return;
            }

            // 启动失败，清理资源后重试
            [self cleanup];

            if (attempt < kEMASLocalProxyMaxRetryAttempts - 1) {
                usleep(kEMASLocalProxyRetryInterval);
            }
        }

        // 所有端口尝试失败
        EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("Proxy service startup failed - tried %ld ports", (long)kEMASLocalProxyMaxRetryAttempts);
        result = NO;
    });

    return result;
}

/**
 *  安全关闭代理服务，释放所有网络资源
 *  包括监听器、活跃连接等
 */
- (void)stop {
    dispatch_sync(_operationQueue, ^{
        // 检查服务状态（双重检查锁定模式）
        if (!self.isProxyReady) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Proxy service not running, no need to stop");
            return;
        }

        EMAS_LOCAL_HTTP_PROXY_LOG_INFO("Stopping proxy service...");

        // 标记服务为停止状态，防止新的连接建立
        self->_isProxyReady = NO;

        // 清理活跃连接
        [self cleanup];

        EMAS_LOCAL_HTTP_PROXY_LOG_INFO("Proxy service stopped successfully");
    });
}

/**
 *  释放监听器、取消活跃连接、重置端口状态
 *  确保资源完全释放，避免内存泄漏
 */
- (void)cleanup {
    // 清理监听器
    if (_listener) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Cancelling network listener");
        nw_listener_cancel(_listener);
        _listener = NULL;
    }

    // Network Framework会自动管理连接生命周期
    // 现有连接会在以下情况自动清理：
    // 1. 客户端断开连接（如URLSession销毁、WebView销毁等）
    // 2. 网络请求完成
    // 3. 连接超时或出错

    // 重置端口状态
    _proxyPort = 0;
}

#pragma mark - 连接处理

/**
 *  接收来自客户端的新的连接请求，进行协议解析和转发
 *  仅支持HTTPS CONNECT协议，适用于各种安全连接客户端（NSURLSession、WKWebView等）
 */
- (void)handleConnection:(nw_connection_t)connection {
    EMAS_LOCAL_HTTP_PROXY_LOG_INFO("New client connection established - connection: %p", connection);

    // 设置连接状态监控
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        switch (state) {
            case nw_connection_state_failed:
            case nw_connection_state_cancelled: {
                // 记录连接失败的详细信息
                if (state == nw_connection_state_failed && error) {
                    nw_error_domain_t domain = nw_error_get_error_domain(error);
                    int code = nw_error_get_error_code(error);
                    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Client connection failed - error domain: %d, error code: %d", domain, code);

                    // 检查是否为系统级严重错误
                    if (domain == nw_error_domain_posix && (code == EADDRINUSE || code == EACCES)) {
                        EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("Detected system-level network error, proxy service may need restart");
                    }
                } else if (state == nw_connection_state_cancelled) {
                    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Client connection disconnected normally");
                }
                break;
            }

            case nw_connection_state_ready:
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Client connection ready");
                break;

            default:
                break;
        }
    });

    // 接收客户端HTTP请求数据
    nw_connection_receive(connection, 1, 4096, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        // 错误处理
        if (error) {
            nw_error_domain_t domain = nw_error_get_error_domain(error);
            int code = nw_error_get_error_code(error);

            if (domain == nw_error_domain_posix && code == 54) {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Client actively disconnected");
            } else {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Receive data error - error domain: %d, error code: %d", domain, code);
            }

            nw_connection_cancel(connection);
            return;
        }

        // 数据有效性检查
        if (!content || dispatch_data_get_size(content) == 0) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Received empty data packet");
            if (is_complete) {
                nw_connection_cancel(connection);
            }
            return;
        }

        // 解析HTTP请求
        NSData *data = [self dataFromDispatchData:content];
        NSString *requestLine = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        // 检查请求是否有效
        if (!requestLine || requestLine.length == 0) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("HTTP request data invalid or cannot be parsed");
            nw_connection_cancel(connection);
            return;
        }

        NSArray *lines = [requestLine componentsSeparatedByString:@"\r\n"];
        if (lines.count == 0) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("HTTP request format invalid: missing request line");
            nw_connection_cancel(connection);
            return;
        }

        NSString *firstLine = lines[0];
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Received HTTP request: %@", firstLine);

        // 分析请求类型
        NSArray *requestParts = [firstLine componentsSeparatedByString:@" "];
        if (requestParts.count >= 2) {
            NSString *method = requestParts[0];
            NSString *target = requestParts[1];
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Request Method: %@, Target: %@", method, target);

            if (![method isEqualToString:@"CONNECT"]) {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Received non-CONNECT request - this will be rejected");
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Only HTTPS CONNECT tunneling is supported");
            }
        }

        // 只处理CONNECT隧道请求
        if ([requestLine hasPrefix:@"CONNECT "]) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Processing CONNECT tunnel request");
            [self handleHTTPSConnect:firstLine fromConnection:connection];
        } else {
            EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("Unsupported request type rejected: %@", firstLine);
            EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("Only CONNECT tunneling is supported");
            nw_connection_cancel(connection);
        }
    });
}

#pragma mark - HTTPS隧道处理

- (void)handleHTTPSConnect:(NSString *)connectLine fromConnection:(nw_connection_t)clientConnection {
    // 解析CONNECT请求格式：CONNECT host:port HTTP/1.1
    NSArray *requestParts = [connectLine componentsSeparatedByString:@" "];
    if (requestParts.count < 3) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("CONNECT request format invalid: %@", connectLine);
        nw_connection_cancel(clientConnection);
        return;
    }

    NSString *method = requestParts[0];
    NSString *hostport = requestParts[1];

    // Validate it's actually a CONNECT request
    if (![method isEqualToString:@"CONNECT"]) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Invalid method, expected CONNECT: %@", method);
        nw_connection_cancel(clientConnection);
        return;
    }

    NSArray *parts = [hostport componentsSeparatedByString:@":"];
    if (parts.count != 2) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("CONNECT request format invalid: %@", hostport);
        nw_connection_cancel(clientConnection);
        return;
    }

    NSString *host = parts[0];
    uint16_t port = (uint16_t)[parts[1] intValue];

    // Validate host and port
    if (host.length == 0 || port == 0) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Invalid host or port: %@:%d", host, port);
        nw_connection_cancel(clientConnection);
        return;
    }

    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("CONNECT host: %@:%d, client: %p", host, port, clientConnection);

    // 解析域名并创建到目标服务器的连接
    NSString *resolvedHost = [self resolveHostname:host];
    nw_connection_t remoteConnection = [self createConnectionToHost:resolvedHost port:port];

    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Establishing HTTPS tunnel connection: %@:%d (resolved: %@)", host, port, resolvedHost);

    // 配置远程连接处理队列
    nw_connection_set_queue(remoteConnection, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));

    // 设置HTTPS隧道连接状态监控
    nw_connection_set_state_changed_handler(remoteConnection, ^(nw_connection_state_t state, nw_error_t error) {
        switch (state) {
            case nw_connection_state_ready: {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("HTTPS tunnel connection established successfully: %@:%d", host, port);

                // 记录IP连接成功
                dispatch_async(self->_ipTrackingQueue, ^{
                    [self clearIPFailure:resolvedHost forHost:host];
                });

                // 发送HTTP 200响应，表示隧道建立成功
                const char *resp = "HTTP/1.1 200 Connection Established\r\n\r\n";
                NSData *respData = [NSData dataWithBytes:resp length:strlen(resp)];
                nw_connection_send(clientConnection, [self dispatchDataFromNSData:respData],
                                 NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false, ^(nw_error_t err) {
                    if (!err) {
                        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Starting HTTPS tunnel bidirectional data relay");
                        // 启动双向透明数据转发
                        [self relayFrom:clientConnection to:remoteConnection];
                        [self relayFrom:remoteConnection to:clientConnection];
                    } else {
                        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Failed to send HTTPS tunnel confirmation response");
                        nw_connection_cancel(remoteConnection);
                        nw_connection_cancel(clientConnection);
                    }
                });
                break;
            }

            case nw_connection_state_failed: {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("HTTPS tunnel connection failed: %@:%d", host, port);

                // 记录IP连接失败
                dispatch_async(self->_ipTrackingQueue, ^{
                    [self recordIPFailure:resolvedHost forHost:host];
                });

                [self sendBadGatewayResponse:clientConnection];
                break;
            }

            case nw_connection_state_cancelled:
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("HTTPS tunnel connection cancelled: %@:%d", host, port);
                nw_connection_cancel(clientConnection);
                break;

            default:
                break;
        }
    });

    // 启动HTTPS隧道连接
    nw_connection_start(remoteConnection);
}

#pragma mark - 数据转发

- (void)relayFrom:(nw_connection_t)source to:(nw_connection_t)destination {
    // 使用专用串行队列进行数据中继，避免递归调用
    dispatch_queue_t relayQueue = dispatch_queue_create("com.alicloud.httpdns.relay", DISPATCH_QUEUE_SERIAL);

    // 启动持续的数据中继循环
    [self scheduleNextReceiveFrom:source to:destination onQueue:relayQueue];
}

- (void)scheduleNextReceiveFrom:(nw_connection_t)source to:(nw_connection_t)destination onQueue:(dispatch_queue_t)queue {
    nw_connection_receive(source, 1, 128 * 1024, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        // 处理接收错误
        if (error) {
            nw_error_domain_t domain = nw_error_get_error_domain(error);
            int code = nw_error_get_error_code(error);

            if (domain == nw_error_domain_posix && code == 54) {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Peer connection closed");
            } else {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Data relay receive error - error domain: %d, error code: %d", domain, code);
            }

            // 发生错误时关闭双向连接
            nw_connection_cancel(source);
            nw_connection_cancel(destination);
            return;
        }

        // 转发有效数据
        if (content && dispatch_data_get_size(content) > 0) {
            // 发送数据到目标连接
            nw_connection_send(destination, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false, ^(nw_error_t sendError) {
                if (sendError) {
                    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Data relay send failed");
                    nw_connection_cancel(source);
                    nw_connection_cancel(destination);
                    return;
                }
            });
        }

        // 处理流结束
        if (is_complete) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Data stream transmission completed");
            nw_connection_cancel(destination);
        } else {
            // 使用队列异步调度下一次接收，避免栈递归
            dispatch_async(queue, ^{
                [self scheduleNextReceiveFrom:source to:destination onQueue:queue];
            });
        }
    });
}

#pragma mark - 数据转换工具

- (NSData *)dataFromDispatchData:(dispatch_data_t)data {
    __block NSMutableData *result = [NSMutableData data];
    dispatch_data_apply(data, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
        [result appendBytes:buffer length:size];
        return true;
    });
    return result;
}

- (dispatch_data_t)dispatchDataFromNSData:(NSData *)data {
    return dispatch_data_create([data bytes], [data length], NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
}

#pragma mark - 辅助方法

/**
 *  在预定义范围内生成范围在[31000, 32000)随机端口，用于避免端口冲突
 */
- (uint16_t)generateRandomPort {
    // 在指定范围内生成随机端口号，避免端口冲突
    uint32_t range = kEMASLocalProxyPortMax - kEMASLocalProxyPortMin;
    uint16_t randomPort = kEMASLocalProxyPortMin + arc4random_uniform(range);
    return randomPort;
}

/**
 *  使用配置的DNS解析器（例如HTTPDNS）解析域名
 *  如果解析失败，返回原始域名使用系统DNS解析
 */
- (NSString *)resolveHostname:(NSString *)hostname {
    // 参数有效性检查
    if (!hostname || hostname.length == 0 || [hostname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Domain parameter invalid, returning original value: %@", hostname ?: @"(null)");
        return hostname ?: @"";
    }

    // 使用自定义DNS解析器获取所有可用IP
    if (self.customDNSResolverBlock) {
        @try {
            NSArray<NSString *> *availableIPs = self.customDNSResolverBlock(hostname);
            if (availableIPs && availableIPs.count > 0) {
                // 使用智能IP选择算法
                __block NSString *selectedIP = nil;
                dispatch_sync(_ipTrackingQueue, ^{
                    selectedIP = [self selectBestIPForHost:hostname fromIPs:availableIPs];
                });

                if (selectedIP && ![selectedIP isEqualToString:hostname]) {
                    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("DNS resolution with IP selection: %@ -> %@ (from %lu available IPs)",
                                                   hostname, selectedIP, (unsigned long)availableIPs.count);
                    return selectedIP;
                } else {
                    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("DNS resolution returned invalid IP, using original hostname: %@", hostname);
                }
            } else {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("DNS resolution returned empty or nil array for hostname: %@", hostname);
            }
        } @catch (NSException *exception) {
            EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("DNS resolver exception: %@, using original domain", exception.reason ?: @"Unknown error");
        }
    } else {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("No custom DNS resolver configured, using system DNS");
    }

    return hostname;
}

/**
 *  从多个IP中选择最佳IP进行连接
 *  优先选择非失败IP，如果都失败则选择失败时间最久的IP
 */
- (NSString *)selectBestIPForHost:(NSString *)hostname fromIPs:(NSArray<NSString *> *)ips {
    if (!ips || ips.count == 0) {
        return hostname;
    }

    NSDictionary<NSString *, NSDate *> *failedIPs = self.failedIPsPerHost[hostname];
    NSDate *now = [NSDate date];
    NSTimeInterval failureTimeout = 300; // 5分钟失败超时

    // 第一轮：寻找首个非失败IP
    for (NSString *ip in ips) {
        NSDate *failureTime = failedIPs[ip];
        if (!failureTime || [now timeIntervalSinceDate:failureTime] > failureTimeout) {
            // IP从未失败或失败已超时，可以使用
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Selected healthy IP: %@ for host: %@", ip, hostname);
            return ip;
        }
    }

    // 所有IP都失败过且未超时 - 选择失败时间最久的IP
    NSString *bestIP = ips[0];
    NSDate *oldestFailure = failedIPs[bestIP];

    for (NSString *ip in ips) {
        NSDate *failureTime = failedIPs[ip];
        if (!oldestFailure || [failureTime compare:oldestFailure] == NSOrderedAscending) {
            oldestFailure = failureTime;
            bestIP = ip;
        }
    }

    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("All IPs failed, selected oldest failure IP: %@ (failed at %@) for host: %@",
                                  bestIP, oldestFailure, hostname);
    return bestIP;
}

/**
 *  记录IP连接失败
 */
- (void)recordIPFailure:(NSString *)ip forHost:(NSString *)hostname {
    if (!ip || !hostname) return;

    // 确保主机名对应的失败字典存在
    if (!self.failedIPsPerHost[hostname]) {
        self.failedIPsPerHost[hostname] = [NSMutableDictionary dictionary];
    }

    self.failedIPsPerHost[hostname][ip] = [NSDate date];
    EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Recorded IP failure: %@ for host: %@", ip, hostname);
}

/**
 *  清除IP的失败记录（连接成功时调用）
 */
- (void)clearIPFailure:(NSString *)ip forHost:(NSString *)hostname {
    if (!ip || !hostname) return;

    if (self.failedIPsPerHost[hostname]) {
        [self.failedIPsPerHost[hostname] removeObjectForKey:ip];
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Cleared IP failure record: %@ for host: %@", ip, hostname);

        // 如果该主机名下没有失败IP了，删除整个记录
        if (self.failedIPsPerHost[hostname].count == 0) {
            [self.failedIPsPerHost removeObjectForKey:hostname];
        }
    }
}

/**
 *  当目标服务器连接失败时，向客户端返回502错误响应
 */
- (void)sendBadGatewayResponse:(nw_connection_t)connection {
    // 发送标准502错误响应
    const char *errorResp = "HTTP/1.1 502 Bad Gateway\r\n"
                           "Content-Length: 0\r\n"
                           "Connection: close\r\n\r\n";

    NSData *errorData = [NSData dataWithBytes:errorResp length:strlen(errorResp)];

    nw_connection_send(connection, [self dispatchDataFromNSData:errorData],
                      NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t err) {
        if (err) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Failed to send 502 error response");
        } else {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Sent 502 error response");
        }
        nw_connection_cancel(connection);
    });
}

/**
 *  创建本地代理到目标服务器的连接
 */
- (nw_connection_t)createConnectionToHost:(NSString *)host port:(uint16_t)port {
    // 创建远程端点（host现在应该已经是解析后的IP地址或原始域名）
    NSString *portString = [NSString stringWithFormat:@"%d", port];
    nw_endpoint_t remoteEndpoint = nw_endpoint_create_host([host UTF8String], [portString UTF8String]);

    // 创建禁用TLS的TCP连接参数（代理本身不加密）
    nw_parameters_t params = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL,
        NW_PARAMETERS_DEFAULT_CONFIGURATION
    );

    // 启用地址重用，便于端口快速重绑定
    nw_parameters_set_reuse_local_address(params, true);

    nw_connection_t connection = nw_connection_create(remoteEndpoint, params);

    // 设置连接队列
    nw_connection_set_queue(connection, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));

    return connection;
}


#pragma mark - 静态API实现

+ (BOOL)isProxyReady {
    // 获取共享实例并返回其就绪状态
    // atomic 属性确保读取操作的线程安全性
    EMASLocalHttpProxy *proxy = [EMASLocalHttpProxy sharedInstance];
    return proxy.isProxyReady;
}

+ (void)setLogLevel:(EMASLocalHttpProxyLogLevel)logLevel {
    _currentLogLevel = logLevel;
}

+ (void)setDNSResolverBlock:(NSArray<NSString *> *(^)(NSString *hostname))resolverBlock {
    EMASLocalHttpProxy *proxy = [EMASLocalHttpProxy sharedInstance];
    proxy.customDNSResolverBlock = [resolverBlock copy];

    if (resolverBlock) {
        EMAS_LOCAL_HTTP_PROXY_LOG_INFO("Custom DNS resolver installed");
    } else {
        EMAS_LOCAL_HTTP_PROXY_LOG_INFO("Custom DNS resolver removed, will use system DNS");
    }
}

+ (BOOL)installIntoWebViewConfiguration:(WKWebViewConfiguration *)configuration {
    // 参数有效性检查
    if (!configuration) {
        EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("WebView configuration object is null, cannot install proxy");
        return NO;
    }

    // 系统版本兼容性检查
    if (@available(iOS 17.0, *)) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("System version supports WKWebView proxy configuration");

        EMASLocalHttpProxy *proxy = [EMASLocalHttpProxy sharedInstance];

        // 创建专用的数据存储，用于隔离代理配置
        NSUUID *dataStoreIdentifier = [[NSUUID alloc] initWithUUIDString:kEMASLocalProxyDataStoreUUID];
        WKWebsiteDataStore *dataStore = [WKWebsiteDataStore dataStoreForIdentifier:dataStoreIdentifier];
        configuration.websiteDataStore = dataStore;

        // 检查代理服务运行状态
        if (!proxy.isProxyReady) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Proxy service not running, clearing WKWebView proxy configuration");
            // 清理代理配置，恢复使用系统网络
            [dataStore setProxyConfigurations:@[]];
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Configured WKWebView to use system network (proxy cleared)");
            return NO;
        }

        // 代理服务正常运行，配置WebView使用本地代理
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Proxy service running normally, starting WKWebView proxy configuration");

        // 创建代理端点配置
        NSString *proxyHost = @"127.0.0.1";
        NSString *proxyPortString = [NSString stringWithFormat:@"%d", proxy.proxyPort];
        nw_endpoint_t proxyEndpoint = nw_endpoint_create_host([proxyHost UTF8String], [proxyPortString UTF8String]);

        // 创建HTTP CONNECT代理配置
        nw_proxy_config_t proxyConfig = nw_proxy_config_create_http_connect(proxyEndpoint, NULL);
        if (proxyConfig) {
            NSArray<nw_proxy_config_t> *proxyConfigs = @[proxyConfig];

            // 检查API可用性并设置代理配置
            if ([dataStore respondsToSelector:@selector(setProxyConfigurations:)]) {
                [dataStore setProxyConfigurations:proxyConfigs];
                EMAS_LOCAL_HTTP_PROXY_LOG_INFO("WKWebView proxy configuration successful - listening address: %@:%d", proxyHost, proxy.proxyPort);
                return YES;
            } else {
                EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("System doesn't support setProxyConfigurations API, enabling fallback mode");
            }
        } else {
            EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("Cannot create proxy configuration object, enabling fallback mode");
        }

        // 配置失败时的降级处理
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("WKWebView proxy configuration failed, will use system network");
        [dataStore setProxyConfigurations:@[]];
        return NO;

    } else {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("System version below iOS 17.0, doesn't support WKWebView proxy configuration, using system network");
        return NO;
    }
}

+ (BOOL)installIntoUrlSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    // 参数有效性检查
    if (!configuration) {
        EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("URLSession configuration object is null, cannot install proxy");
        return NO;
    }

    // 系统版本检查 - 要求iOS 17.0+
    if (@available(iOS 17.0, *)) {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("System version supports URLSession proxy configuration");

        EMASLocalHttpProxy *proxy = [EMASLocalHttpProxy sharedInstance];

        // 检查代理服务运行状态
        if (!proxy.isProxyReady) {
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Proxy service not running, clearing URLSession proxy configuration");
            // 清理代理配置，恢复使用系统网络
            configuration.proxyConfigurations = @[];
            EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Configured URLSession to use system network (proxy cleared)");
            return NO;
        }

        // 代理服务正常运行，配置URLSession使用本地代理
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("Proxy service running normally, starting URLSession proxy configuration");

        // 创建代理端点配置
        NSString *proxyHost = @"127.0.0.1";
        NSString *proxyPortString = [NSString stringWithFormat:@"%d", proxy.proxyPort];
        nw_endpoint_t proxyEndpoint = nw_endpoint_create_host([proxyHost UTF8String], [proxyPortString UTF8String]);

        // 创建HTTP CONNECT代理配置
        nw_proxy_config_t proxyConfig = nw_proxy_config_create_http_connect(proxyEndpoint, NULL);
        if (proxyConfig) {
            configuration.proxyConfigurations = @[proxyConfig];
            EMAS_LOCAL_HTTP_PROXY_LOG_INFO("URLSession proxy configuration successful (iOS 17.0+ API) - listening address: %@:%d", proxyHost, proxy.proxyPort);
            return YES;
        } else {
            EMAS_LOCAL_HTTP_PROXY_LOG_ERROR("Cannot create proxy configuration object");
            configuration.proxyConfigurations = @[];
            return NO;
        }
    } else {
        EMAS_LOCAL_HTTP_PROXY_LOG_DEBUG("System version below iOS 17.0, URLSession proxy configuration not supported");
        return NO;
    }
}


@end
