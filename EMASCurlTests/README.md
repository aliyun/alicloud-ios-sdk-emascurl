# 测试说明
EMASCurl是基于libcurl封装实现的应用层网络库，重在提供一套方便的接口可以桥接到NSURLSession，同时提供方便的接入HTTPDNS的方法，使得业务可以尽量无感接入。

在设计测试用例时，我们的关注点不是网络请求本身的正确性或者性能，因为这由libcurl来保障。EMASCurl的测试用例更应该关注桥接之后的NSURLSession的功能正确性，比如超时设置、中途取消、进度回调等。

# 测试前提
为了测试用例不依赖外部服务稳定性或者网络稳定性，测试中我们需要起一个MockServer提供测试用的HTTP服务。相关文件放在`../MockServer`路径下。

运行以下命令，会同时启动一个监听在9080端口的HTTP1.1服务和一个监听在9443端口的HTTP2服务：

```python
python3 server.py
```

# 测试用例
测试用例包含以下这些场景
- 基本的GET、PUT、POST、DELETE、OPTION、HEAD请求
- 重定向
- 数据下载场景和中途取消
- 数据上传场景和中途取消

# 缓存回归与并发验证

`EMASCurlCacheRegressionTest` 的 5 个功能用例不需要 MockServer，也不访问网络：覆盖带正确时间戳的外部缓存夹具、SDK 存取、过期响应的验证器策略、304 响应合成。每个用例使用独立内存缓存，分别观察 Foundation 命中与 SDK 返回，避免把 SDK 返回 nil 当成底层未命中。

```sh
xcodebuild test -project EMASCurl.xcodeproj -scheme EMASCurlTests \
  -destination 'platform=iOS Simulator,id=<模拟器 UDID>' \
  -only-testing:EMASCurlTests/EMASCurlCacheRegressionTest \
  CODE_SIGNING_ALLOWED=NO
```

真机使用 `platform=iOS,id=<设备 UDID>`，去掉 `CODE_SIGNING_ALLOWED=NO`，并提供 `DEVELOPMENT_TEAM=<开发团队>`。测试 target 在 iphoneos 下使用空白 `EMASCurlTestHost`，无需 Demo 或 Pods；需要有效开发签名与设备授权。模拟器保持无宿主测试。

`EMASCurlCacheStressTest` 包含两个可以被 XCTest 发现的正常并发场景：双 reader + SDK store，以及双 reader + 304 update。每个 reader 都把返回值交给自己的串行 client 队列；client 在 producer 的局部 pool 排空后才使用它。304 返回值也经过同样交接。它覆盖队列外持有与释放引用的路径，但不保证每个对象的最终释放时机，也不保证逻辑 reader 始终由不同 OS 线程执行。

压力场景默认通过 `XCTSkip` 跳过；不要把随机崩溃压力验证用作每次 CI 的稳定性门禁。设置 `EMASCURL_CACHE_STRESS_ITERATIONS` 才会执行，默认推荐每 worker 20,000 次。以下脚本会将变量写入 `.xctestrun`，逐轮保存原始日志、结果包和 JSON，并交替前后构建的执行顺序：

```sh
xcodebuild build-for-testing -project EMASCurl.xcodeproj -scheme EMASCurlTests \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/emascurl-head-build CODE_SIGNING_ALLOWED=NO

python3 EMASCurlTests/run_cache_stress.py \
  --variant baseline=/absolute/baseline-build/Build/Products/<名称>.xctestrun \
  --variant head=/tmp/emascurl-head-build/Build/Products/<名称>.xctestrun \
  --destination 'platform=iOS Simulator,id=<模拟器 UDID>' \
  --iterations 20000 --rounds 3 --output /tmp/emascurl-cache-results
```

输出目录必须不存在，variant 名称必须唯一。真机先按同一配置分别 `build-for-testing`，将 destination 改为具体设备即可。为隔离本次 pool 改动，对照构建使用同一份测试和 head 源码，仅将 baseline 的 `EMASCurlResponseCache.m` 替换为改动前版本；不能拿不同线程模型、容量或命中层级的旧实验混作同一对照。

判定以完整进程记录为单位：SDK 返回数、client 回调数和内容校验均正确才能通过。条目被驱逐导致 nil 属于结果不匹配；缺少结果行时须查看 `.xcresult` 区分启动失败、超时和崩溃，不能一概记为崩溃。未崩溃既不证明窗口关闭，也不能换算为现网崩溃率下降。

还应记录 Xcode 注入的诊断库。本轮真机使用的初始 `.xctestrun` 注入了 `libRPAC.dylib`，异常记录中同时存在检查器栈、SDK lookup 栈及无法归因的记录；未做关闭后的对照，不能把所有异常退出都归为 SDK 崩溃。

本次已完成结果及证据边界见 [CacheValidationResults.md](CacheValidationResults.md)，客户说明见 [1.5.7 发布说明](../ReleaseNotes/1.5.7.md)。旧 `EMASCurlCacheUAFTest` 仍作为不自动执行的历史诊断记录，不属于上述正常 API 验证的执行范围。
