# Enhanced Metrics Output Example

## Overview
The EMASCurl library now provides comprehensive performance metrics equivalent to URLSessionTaskTransactionMetrics. The test case has been enhanced to display all available metrics in a structured format.

## Enhanced Test Output

When running the test case, you'll see output similar to this:

```
=== 综合性能指标 (EMASCurlTransactionMetrics) ===
请求成功: 是
错误信息: 无
请求URL: https://example.com/api/data

--- 时间戳信息 ---
获取开始时间: 2024-12-17 10:30:15.123
域名解析开始: 2024-12-17 10:30:15.125
域名解析结束: 2024-12-17 10:30:15.145
连接开始时间: 2024-12-17 10:30:15.146
安全连接开始: 2024-12-17 10:30:15.200
安全连接结束: 2024-12-17 10:30:15.280
连接结束时间: 2024-12-17 10:30:15.281
请求开始时间: 2024-12-17 10:30:15.282
请求结束时间: 2024-12-17 10:30:15.285
响应开始时间: 2024-12-17 10:30:15.450
响应结束时间: 2024-12-17 10:30:15.920
总耗时: 0.797s

--- 各阶段耗时分析 ---
域名解析耗时: 0.020s (20ms)
TCP连接耗时: 0.135s (135ms)
SSL/TLS握手耗时: 0.080s (80ms)
请求发送耗时: 0.003s (3ms)
响应接收耗时: 0.470s (470ms)

--- 网络协议信息 ---
网络协议: http/2
代理连接: 否
连接重用: 否

--- 传输字节统计 ---
请求头字节数: 156 bytes
请求体字节数: 0 bytes
响应头字节数: 342 bytes
响应体字节数: 1048576 bytes

--- 网络地址信息 ---
本地地址: 192.168.1.100:52345
远程地址: 203.0.113.10:443

--- SSL/TLS信息 ---
TLS协议版本: TLS
TLS密码套件: ECDHE-RSA-AES128-GCM-SHA256

--- 网络类型信息 ---
蜂窝网络: 否
昂贵网络: 否
受限网络: 否
多路径网络: 否
========================================
```

## Key Metrics Provided

### 1. **时间戳信息** (Timestamp Information)
- 获取开始时间: Request fetch start time
- 域名解析开始/结束: DNS resolution start/end times
- 连接开始/结束时间: TCP connection start/end times
- 安全连接开始/结束: SSL/TLS handshake start/end times
- 请求开始/结束时间: Request transmission start/end times
- 响应开始/结束时间: Response reception start/end times

### 2. **各阶段耗时分析** (Phase Timing Analysis)
- 域名解析耗时: DNS lookup duration
- TCP连接耗时: TCP connection duration
- SSL/TLS握手耗时: SSL/TLS handshake duration
- 请求发送耗时: Request transmission duration
- 响应接收耗时: Response reception duration

### 3. **网络协议信息** (Network Protocol Information)
- 网络协议: HTTP version (http/1.0, http/1.1, http/2, http/3)
- 代理连接: Whether proxy was used
- 连接重用: Whether connection was reused

### 4. **传输字节统计** (Transfer Byte Statistics)
- 请求头字节数: Request header bytes sent
- 请求体字节数: Request body bytes sent
- 响应头字节数: Response header bytes received
- 响应体字节数: Response body bytes received

### 5. **网络地址信息** (Network Address Information)
- 本地地址: Local IP address and port
- 远程地址: Remote IP address and port

### 6. **SSL/TLS信息** (SSL/TLS Information)
- TLS协议版本: TLS protocol version
- TLS密码套件: TLS cipher suite

### 7. **网络类型信息** (Network Type Information)
- 蜂窝网络: Whether using cellular network
- 昂贵网络: Whether network is expensive
- 受限网络: Whether network is constrained
- 多路径网络: Whether multipath is supported

## Implementation Details

The enhanced metrics are extracted from libcurl using these CURLINFO_* constants:

- `CURLINFO_HTTP_VERSION`: HTTP protocol version
- `CURLINFO_LOCAL_IP`/`CURLINFO_LOCAL_PORT`: Local network endpoint
- `CURLINFO_PRIMARY_IP`/`CURLINFO_PRIMARY_PORT`: Remote network endpoint
- `CURLINFO_SIZE_UPLOAD_T`/`CURLINFO_SIZE_DOWNLOAD_T`: Transfer byte counts
- `CURLINFO_USED_PROXY`: Proxy usage detection
- `CURLINFO_TLS_SSL_PTR`: SSL/TLS session information
- `CURLINFO_CERTINFO`: Certificate details

Network type detection uses iOS system APIs:
- `SCNetworkReachability` for cellular network detection
- System configuration APIs for network characteristics

## Usage in Tests

The test case now provides comprehensive validation of all metrics:

```objc
// 测试使用新的全局综合性能指标回调
[EMASCurlProtocol setGlobalTransactionMetricsObserverBlock:^(NSURLRequest * _Nonnull request, BOOL success, NSError * _Nullable error, EMASCurlTransactionMetrics * _Nonnull metrics) {
    // Comprehensive metrics logging with all available data
    // ... (detailed logging as shown above)
}];
```

This provides complete visibility into network request performance and characteristics, equivalent to iOS native URLSessionTaskTransactionMetrics.