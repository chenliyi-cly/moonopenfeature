# 安全边界与集成责任

本库是进程内同步 SDK，不是沙箱、授权系统或规则服务器。它不提供网络 transport、凭据管理、远程配置拉取或数据加密。Provider、hooks 和 event handlers 都是受信任的应用代码；SDK 不会限制它们的文件、网络或进程权限。本文不构成安全审计或无漏洞声明。

## 错误不等于 panic 隔离

公共 callbacks 使用 Result（resolver 使用 Resolution 中的错误）表达预期失败。Evaluation 在这些错误路径返回调用者 default；error/finally observer 的 Err 被收集，其他 observers 继续。标准 `Client::track` 返回 Unit 并记录失败，`track_checked` 才返回 Result 扩展。

**panic、abort、运行时陷阱、OOM、无限循环和阻塞 callback 不被捕获或隔离。** 不要将“不传播 Result 错误”宣传为“任意用户代码都不会使进程失败”。需要隔离不受信任 provider 时，应用应建立额外进程/权限边界。

Default 应由业务按风险选取；SDK 不知道 true/false 哪个更安全。Feature flags 不能代替身份认证、权限检查或计费校验。

## 数据输入与复制

- JSON 校验拒绝循环容器、非有限 number 和非法 numeric repr；root depth 为零，最多 64 条容器边。Context envelope 会消耗一层预算。
- 深拷贝隔离 context、结构 flag、hints、tracking details 等边界，降低 callback 修改输入污染后续调用的风险。HookData 是特意共享于单 hook 的阶段间的数据，不是全局 store。
- `copy_json` 对不合法输入回退 null，不是错误报告 API；需要可见错误时先 validate。无效 default 的复制/序列化不能被当作精确保留任意畸形值的保证。
- 结构 flag 接受 JSON object/array/null；整数为 Int64，浮点需有限。Context/HookData 的 JSON 模型没有原生 Datetime 或任意对象能力。
- 公开 enum/record 允许直接构造，可能绕过安全 constructor，例如 TrackingEvent 的空 key/nonfinite value 检查。不要把公开类型当作已验证输入；优先使用 constructors 并在 provider 边界验证。
- 序列化的 targetingKey 使用保留字段语义；避免以同名普通 attribute 承载其他含义，并测试 round-trip。JSON 的编码不是脱敏或加密。

Depth 限制不限制总字符串长度、对象宽度、数组长度或复制总成本；宽大输入仍可能消耗大量 CPU/内存。应用应限制请求体、属性数量、payload 大小和调用频率。没有时间预算或 callback timeout。

## Diagnostics 与隐私

SDK 不主动写日志或发送 telemetry；但 provider/hook 代码可以自行发送数据。传入的 targeting key、context、hints、HookData、tracking details 和 error message 都可能含敏感信息。只传业务必需属性；不要放入访问凭据或原始身份资料。HookData JSON-only 并不意味着隐私安全。

Diagnostics 可能保留 callback 提供的 message；每个 buffer 最多 128 条，读取 `take_diagnostics` 会排空对应存储。SDK 聚合多个 buffer，单次返回总数不一定小于 128。应用在持久化诊断前应脱敏、限制访问和保存期限；上限意味着可能丢失较早错误，不能作为完整审计日志或交易送达证据。

## Lifecycle 与重入

Callbacks 同步执行，可重入；EventBus 对重入事件排队，每次排空最多 1024 个，超额丢弃并记录 diagnostic，不能依赖无限事件链必达。listener 快照不是线程锁。Sdk 的 lifecycle mutation guard 也不构成线程安全或并发请求隔离。

关闭后的 SDK 不可复用，保留 terminal bindings；现有 clients 不再运行 resolver。SDK 级 hooks/handlers/global context 被清除，但外部持有的 Provider、Client、callback closure、已导出的 Json 及 diagnostics 不会因此被安全擦除。Client 的局部 context/hooks 仍可能持有引用。不要把 shutdown 当作密码学清零。

Provider 初始化/事件协议不合规会造成状态、回调观察不一致。显式发 READY/ERROR；不要依赖返回 Ok/Err 来自动广播状态。不要跨独立 SDK 共享可变 Provider 并期待生命周期独立。

## 明确不提供

- 自动 async/thread/task transaction-context 传播、线程安全保证或 callback 沙箱。
- Tracking 持久队列、重试、去重、exactly-once、自动关联上次 evaluation 或网络送达保证。
- 本地规则/rollout 决策、签名验证、配置鉴权或恶意 provider 检测。

安全检查与测试应以当前源码为准。本文作者只进行了只读源码审查和文档更新，未宣称运行渗透测试、外部审计或完整测试套件。若维护者后续增加 transport 或凭据支持，应重新定义威胁模型和数据流，而非沿用本文的“无 transport”边界。
