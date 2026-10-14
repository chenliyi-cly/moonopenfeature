# 架构与运行边界

本项目是 provider-neutral 的同步 MoonBit SDK 核心，不是本地规则、分群、rollout 或实验决策引擎。Provider 决定 flag 的值；SDK 负责类型、默认值、上下文、hooks、绑定及事件。当前实现是部分 OpenFeature 语义的独立重写，不声明完整符合或通过官方认证。规范差异见 [conformance.md](conformance.md)。

## 组件

| 源文件 | 职责 |
| --- | --- |
| `values.mbt`, `typed.mbt` | Boolean / Int64 / Double / String / JSON Structure；typed value 与 detailed API，禁止类型强制转换 |
| `context.mbt`, `context_json.mbt` | targeting key、JSON attributes、按键覆盖合并、校验及深拷贝 |
| `resolution.mbt`, `metadata.mbt`, `errors.mbt` | provider resolution、应用 details、标量 flag metadata、开放 reason 字符串与标准错误码 |
| `options.mbt` | invocation context、显式 transaction-context 参数、invocation hooks、hints 的快照 |
| `hooks.mbt`, `hook_data.mbt` | 固定 hook plan、正向 before、逆向 after/error/finally、每 hook/evaluation 的 JSON-only scratch store |
| `provider.mbt` | 同步 callback adapter、显式 lifecycle events、domain-scoped 选项和 first binding domain 查询 |
| `sdk.mbt` | 独立 SDK 实例、默认/named bindings、动态事件路由、生命周期管理和 diagnostics |
| `client.mbt`, `tracking_model.mbt`, `events.mbt` | live domain client、tracking、同步事件分发与晚注册状态回放 |

`Sdk::new()` 创建互不共享配置的对象，并绑定返回调用者 default 的 No-op provider。没有隐式进程全局 singleton，也不读取环境配置或远程配置。不要跨 SDK 实例共享可变 Provider：实例会共享 lifecycle/status/event bus，而不会因 SDK 独立就自动隔离。

## Evaluation 路径

1. 从 default 确定预期类型并校验；无效 default 直接产生错误 details，当前早退路径不会执行 hooks。
2. 固定 options、provider 和 hook plan；client 是 live domain handle，每次调用重新解析 provider，未知 domain 回退 default provider。
3. 合并上下文：`SDK global → explicit transaction → client → invocation`。高优先级按键整体覆盖，不递归合并嵌套对象。后层 targeting key 缺失时继承，存在时覆盖，包括空字符串。
4. before 按 `API → Client → Invocation → Provider` 执行；各层按注册顺序。每个返回 overlay 立即合并，下一 before 能看到更新。
5. 若 before 无错误且 SDK 未关闭，调用 provider resolver。NotReady/Shutdown/Fatal 被阻止；Error/Stale 允许 provider 自行决策。此 gate 是本项目行为，不是声称规范禁止在所有非 Ready 状态求值。
6. 校验 resolution 类型和 JSON。错误使用 default；成功运行逆序 after。after 返回 Err 也转 default/error details。
7. 出错时逆序 error；所有路径逆序 finally。finally 使用最终应用 details。error/finally 的 Result Err 进入 diagnostics，不改写原结果，不阻断剩余同阶段 hooks。

逆序是整个 plan 的逆序，包含每层内部顺序。Callback 取得的 context/hints/details 使用复制边界；before 通过返回新 context 改变此次 evaluation，不回写持久 context。HookData 则有意在该 hook 的阶段间共享，同一 plan 内每 hook 独立，不同 evaluation 重新创建；只接受通过校验的 JSON，不支持任意 MoonBit 对象。

## Provider 与 domain

`Provider::new` 接受 resolver，以及可选 initialize/shutdown/track/context_changed 同步 callbacks。预期失败用 Result 或带错误的 Resolution 表示；panic/abort 不会被 SDK 捕获。

SDK 在 initialize 前建立事件订阅。存在 initialize callback 时，callback 必须自行调用 `emit_ready` 或 `emit_error`；成功返回不会自动发 READY。没有 initialize callback 才由适配器标 Ready 并发 READY。当前 initialize 返回 Err 会直接记录 Error/Fatal 状态但不发事件；这是已披露的规范差异，不应作为 provider 的正常事件协议。

一个 provider 的初始化尝试至多一次；失败也不自动重试。`domain_scoped=true` 拒绝第二个不同 domain；`binding_domain()` 查询首次绑定 domain，callback 可以通过 provider 参数获取。默认 domain 内部使用空字符串，因此此查询不是规范可选 domain 参数的逐字签名。共享 provider 最后一个绑定移除后才 retire/shutdown。

Ready/Stale/Error/Fatal 由 emit 方法维护；CONFIGURATION_CHANGED 不改变 readiness。Fatal 和 Shutdown 是终态，不因后来的 READY 通知恢复。SDK-wide `on` 收到每 provider event 一次；domain fan-out bus 用于匹配当前关联 clients。Client handlers 随绑定替换继续存在。

`Client::on` 晚注册时，对 Ready、Error/Fatal 对应的 ERROR、Stale 立即回调；不重放 CONFIGURATION_CHANGED 历史。`Sdk::on` 的即时状态回放检查默认 provider，不枚举全部 named providers；后续新事件仍来自所有被观察 providers。

## Tracking

`Client::track` 返回 Unit，provider 返回的 Err 进入 SDK diagnostics。`track_checked` 是返回 Result 的本地扩展，供需要观察失败的集成使用。两者传给 provider 的 context 均为 `global → explicit transaction → client → invocation`，不执行 evaluation hooks，也不继承此前 before 的局部 overlay。不支持 tracking 的 provider 是 no-op。

`TrackingEvent::new` 校验非空 key、有限 numeric value 并复制 details；absent value 与零不同。公开 record 构造可以绕过 constructor 校验，调用者应优先使用 constructor。track 没有后台队列、重试、持久化或送达保证，provider callback 可能阻塞。

## Shutdown、事件和并发

SDK shutdown 先 closed，再解绑观察并关闭 providers；清除 SDK hooks、handlers、global context 和 known-domain 路由信息。bindings 保留 terminal provider，供现有 clients 观察失败；SDK 对象不可重开，需新建 Sdk。Client 自身的 context/hooks 不是全局状态，不因此自动清空；不要把 closed SDK 当成已恢复的空白可复用实例。当前 provider 对外显示 Shutdown，而非规范的 NotReady；见符合性差异。

EventBus 是同步、可重入排队的单执行流对象。每个事件使用 listener 快照，回调内增删影响下次事件；Result Err 不阻断其他 listeners。单次排空至多处理 1024 个事件，超额丢弃并记 diagnostic；每个 diagnostic buffer 保留最近 128 条。这些上限是本地保护，不是规范保证或完整资源配额。

不提供线程安全、async evaluation、自动 transaction propagation、static-context reconciliation、网络 transport 或隔离执行用户 callbacks。显式 transaction 参数仅是调用输入，不是 thread/task-local propagator。同步 callback 也不等于非阻塞。

## 重入事件的所有权快照

Provider bus 的 package-private SDK 路由监听器先于普通监听器执行；普通监听器仍按注册顺序执行。SDK 在 API observers 运行前冻结 domain recipients，因此先注册的 provider observer 或 API observer 更换绑定也不能让原事件丢失。API bus 每 provider event 投递一次，domain bus 为当时关联的各 client domain 分发；不是把每个 domain 副本再次交给全局 API observers。SDK 与 EventBus 的快照各保护一个层级：前者冻结绑定所有权，后者冻结监听器列表。回调中 shutdown 清空监听器是显式停止，不保证关闭后仍继续投递。
