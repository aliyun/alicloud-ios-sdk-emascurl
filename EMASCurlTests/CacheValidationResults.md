# CR 29868292 缓存验证结果（2026-09-09）

本次按“修复部分竞态条件下的缓存崩溃”评估，测试补充未修改 SDK 生产代码。已完成的功能回归通过；并发验证仍观察到 SDK 缓存查询路径异常。现有数据不能用于承诺崩溃率降幅，也不能证明所有缓存生命周期窗口已关闭。本轮按用户要求基于已有记录收尾，不继续扩大试验。

## 评审意见处理

- G1c 停止标记改用 C11 atomic；外部写入夹具补充存储时间戳，分别观察 Foundation 命中与 SDK 返回值。原夹具的 `SDK hits=0` 不等于底层 lookup 未命中，也不能据移除调用认定条目已同步删除。
- 新增 5 个自动功能用例，以及 2 个显式启用的正常 API 并发场景和真机宿主。并发场景覆盖双 reader 向 client 队列交接返回值，以及 304 更新、存入、返回的路径；不保证每个对象都在 client 队列发生最终释放。
- lookup / 304 返回原 wrapper 及其他组件访问共享缓存的残留风险继续保留在本版范围说明中。修正“最终释放全部回到串行区”“唯一变量对照”“防御性副本已证伪”等超出证据的表述。
- 86400 秒空闲超时上限及正小数向上取整属于兼容性变化，已写入 [1.5.7 发布说明](../ReleaseNotes/1.5.7.md)。

## 环境与对照定义

- head：`9e5581b240c59091f5feee98a27a3311f6bf559b`，叠加本轮测试。
- baseline：同一 head 与同一测试，仅将 `EMASCurl/EMASCurlResponseCache.m` 替换为 `5b733cb` 的文件，用于隔离三处 pool 差异；不是完整 master 构建。
- Xcode 26.6（17F113），Debug，ASan / TSan / Zombies 均未开启。**本轮真机使用的初始 `.xctestrun` 注入了 Xcode `libRPAC.dylib`；未做关闭后的对照。**
- 模拟器：iPhone 17 Pro，iOS 26.5（23F77），arm64。真机：iPhone 15 Pro Max，iOS 18.5（22F76），arm64e；不使用设备名称中的旧版本号推断系统版本。
- 并发参数：独占 NSURLCache，4 MiB 内存、0 磁盘、8 个 key、16 字节正文；两个 reader 各 20,000 次，另一个 worker 执行 20,000 次 store 或 304。每个构建、每个场景各 3 轮，交替构建顺序。
- 输入在并发前固定，回调强持有返回对象，计数使用 atomic。本轮运行未包含外部共写、私有 Foundation API 或故障注入。

## 功能回归

| 最终验证环境 | 功能用例 | 压力用例默认行为 |
| --- | --- | --- |
| iOS 26.5 模拟器，宿主配置调整后 | 5/5 通过，0 失败 | 2 个跳过 |
| iOS 18.5 真机 | 5/5 通过，0 失败 | 2 个跳过 |

功能用例覆盖有效外部夹具、SDK 存取内容、过期响应的验证器策略和 304 合成。结果见 [模拟器最终摘要](results/cache-20260909/functional-simulator-final-summary.json) 与 [真机摘要](results/cache-20260909/functional-device-summary.json)。

## 并发验证

下表按完整轮次与异常栈分类记录，不把测试进程的所有异常退出混算成 SDK 崩溃。

| 环境与场景 | baseline | head |
| --- | --- | --- |
| 模拟器，store + 双 reader | 3/3 完成 | 3/3 完成 |
| 模拟器，304 + 双 reader | 2/3 完成；第 3 轮 SDK lookup 栈崩溃 | 2/3 完成；第 1 轮 SDK lookup 栈崩溃 |
| 真机，store + 双 reader | 2/3 完成；第 2 轮 libRPAC 栈异常 | 2/3 完成；第 1 轮 libRPAC 栈异常 |
| 真机，304 + 双 reader | 0/3 完成；1 个 SDK lookup 栈、1 个 libRPAC 栈、1 个未归因 abort | 0/3 完成；1 个 SDK lookup 栈、1 个 libRPAC 栈、1 个缺崩溃附件 |

所有完整轮次均返回 40,000 个 SDK 可用响应，完成 40,000 次 reader client 回调，内容异常为 0。完整的 304 轮次另有 20,000 个更新返回值及对应回调。异常轮次缺少完整计数，不计作零命中，也不纳入完成轮次的操作计数。

模拟器两份 `.ips` 均为 `EXC_BAD_ACCESS / SIGSEGV`，队列是 `com.alicloud.emascurl.cacheQueue`：

- head 第 1 轮：`objc_msgSend` → `emas_isResponseStillFreshForRequest:`（类别文件第 309 行）→ `cachedResponseForRequest:` block（第 125 行）。
- baseline 第 3 轮：`objc_msgSend` → `cachedResponseForRequest:` block（改动前文件第 114 行，Vary 检查）。

真机 12 轮中 4 轮完整、8 轮异常，8 轮进一步区分为：

| 栈证据分类 | 轮次 | 证据边界 |
| --- | --- | --- |
| 4 份 libRPAC 栈 | head store 第 1 轮、baseline store 第 2 轮、head 304 第 1 轮、baseline 304 第 3 轮 | 落在 `qosWaiterSignallerInvariantCheck` / `interposed_dispatch_semaphore_wait`。不能直接归为 SDK 缓存崩溃，也未唯一证实性能检查器本身存在缺陷。 |
| 2 份 SDK lookup 栈 | baseline 304 第 1 轮、head 304 第 2 轮 | 前者为 `objc_retain` → `emas_cacheControlDirectives` → freshness；后者为 `objc_msgSend` → lookup。两者均落在 SDK cacheQueue 查询路径。 |
| 1 份未归因 abort | baseline 304 第 2 轮 | 仅确认 abort，未归因到 SDK 或检查器。 |
| 1 份缺崩溃附件 | head 304 第 3 轮 | XCTest 摘要报告 segv；缺少可供归因的崩溃附件。 |

这些记录支持“测试环境中仍可观察到 SDK 查询路径异常”，但栈本身不能唯一证明 CFNetwork 回指针的具体机制。真机结果还受到已注入检查器这一未排除因素的限制。不能以 8 次异常退出计算 SDK 崩溃率，也不能据两版本的少量轮次比较发生概率、宣称 pool 无效或引入回归。

## 原始证据与状态

- 逐轮计数：[模拟器](results/cache-20260909/simulator-stress.json)、[真机](results/cache-20260909/device-stress.json)。
- 栈摘录：[模拟器](results/cache-20260909/simulator-crash-stacks.json)、[真机](results/cache-20260909/device-crash-stacks.json)；真机 XCTest 摘要见 [device-failure-summaries.json](results/cache-20260909/device-failure-summaries.json)。
- 模拟器失败摘要：[head 304 第 1 轮](results/cache-20260909/head-304-round1-summary.json)、[baseline 304 第 3 轮](results/cache-20260909/baseline-304-round3-summary.json)。[manifest.json](results/cache-20260909/manifest.json) 记录源文件校验值、参数及分类口径。
- 完整日志、`.xcresult` 和诊断留存在 `bliss@10.88.88.2:/tmp/emascurl-tests-20260909.VsMxlL`；JSON 保留各轮路径。`diagnostics-baseline` 可能包含较早的 head 报告，应按进程、时间和构建匹配，避免重复计数。

本轮没有合并或重新验证 CR 中既有 `3/36 → 0/72` 等历史实验数据；负载不同，不能混作本轮对照。未执行关闭 libRPAC 后的补充实验。

测试补充、结果记录与 [客户发布说明](../ReleaseNotes/1.5.7.md) 保存在 `codex/cr29868292-cache-tests` 补充分支，供 CR 29868292 核对；本文件不代表版本已发布。评论处理状态以 CR 中的实际记录为准。
