# OpenFeature 语义覆盖与已知差异

## 声明与固定依据

**这是部分语义实现，不声明 full conformance、官方认证、完整官方测试通过或与任意 SDK 逐行为等价。** 此表基于 2026-10-14 集成阶段的源码阅读；描述有实现或有本地测试源码，不表示本次文档工作执行了这些测试。功能可能继续变化，发布前需重新核对。

规范权威：OpenFeature spec **v0.9.0**，commit **`d5b0a734d8cb9b42bf89be2a97c627f58208e811`**。
行为参考而非规范权威：Go SDK **v1.19.0**，commit **`5540b6a49436ba4687cfcc530e570caa6d472e40`**。二者 Apache-2.0；出处见 [THIRD_PARTY.md](../THIRD_PARTY.md)。

固定章节：
- [§1 Evaluation / API / lifecycle / isolation](https://github.com/open-feature/spec/blob/d5b0a734d8cb9b42bf89be2a97c627f58208e811/specification/sections/01-flag-evaluation.md)
- [§2 Providers](https://github.com/open-feature/spec/blob/d5b0a734d8cb9b42bf89be2a97c627f58208e811/specification/sections/02-providers.md)
- [§3 Context](https://github.com/open-feature/spec/blob/d5b0a734d8cb9b42bf89be2a97c627f58208e811/specification/sections/03-evaluation-context.md)
- [§4 Hooks](https://github.com/open-feature/spec/blob/d5b0a734d8cb9b42bf89be2a97c627f58208e811/specification/sections/04-hooks.md)
- [§5 Events](https://github.com/open-feature/spec/blob/d5b0a734d8cb9b42bf89be2a97c627f58208e811/specification/sections/05-events.md)
- [§6 Tracking](https://github.com/open-feature/spec/blob/d5b0a734d8cb9b42bf89be2a97c627f58208e811/specification/sections/06-tracking.md)
- [Types and data structures](https://github.com/open-feature/spec/blob/d5b0a734d8cb9b42bf89be2a97c627f58208e811/specification/types.md)

“实现”表示所列路径可见；“partial/差异”不能通过改名消除。SHOULD 未实现应披露，不冒称违反无条件 MUST；条件不适用与实现缺口分开记录。

## 功能矩阵

| 条款 | 当前源码行为 | 状态 / 边界 |
| --- | --- | --- |
| 1.3.1.1, 1.3.3.1, 1.4.1.1 | Boolean/Int64/Double/String/JSON Structure 的 value/details API | 实现同步 dynamic-context 路径；非完整任意原生结构模型 |
| 1.3.4, 1.4.5–10 | 类型精确校验、原 key、reason/variant、错误/default、标准错误码 | Result/Resolution 错误路径实现；panic/abort 不捕获，不能宣称普遍 no-throw |
| 1.4.14–15 | flag metadata 为独立标量 record，缺省空 record，复制访问 | 实现相关模型 |
| 1.4.12 SHOULD | 无 async/nonblocking evaluation | 未实现；同步 callback 可能阻塞 |
| 3.1.1–4, 4.2.1 | 可选 targeting key、按键/all-pairs 查询、JSON attributes/hints | partial：无原生 Datetime；把日期装成普通字符串不是完整 Datetime 支持 |
| 3.2.1.1, 3.2.3 | global → 显式 transaction → client → invocation → before，重复键覆盖 | 实现；结构整体替换，不做递归 deep merge |
| 3.3 | options/track 显式 transaction_context 参数 | 扩展；无自动 propagator/current transaction 存取或异步隔离，不宣称实现该传播机制 |
| 4.3.4–5, 4.4.1–2 | before 正向逐步 overlay；after/error/finally 整体逆序 | 实现；每次 evaluation 固定 plan |
| 4.4.3–7 | before/after Err 中止该阶段；error/finally Err 继续并记录 | Result 路径实现；panic 不在此保证中 |
| 4.3.2, 4.6.1 | 每 hook/evaluation 的可变 HookData，阶段间保留 | partial：JSON-only，不满足任意类型值要求，不能存原生 span/opaque handle |
| 1.1.2–3, 1.1.6 | 默认/named provider，client 动态绑定、共享实例最后绑定关闭 | 实现同步生命周期；无异步 set-and-wait |
| 1.1.8.1, 2.4.1–4 | domain_scoped bool、首次 domain 查询、一次初始化尝试 | 实现适配；domain 经 Provider.binding_domain 查询，非 initialize 的独立可选参数；默认用空字符串 |
| 2.8.2–3 | 有 initialize callback 时不根据返回值合成 READY/ERROR；无 callback 自动 READY | 显式事件路径实现；Err 直接更新状态的差异见下文 |
| 5.1–2, 5.3.5 | READY/ERROR/STALE/configuration-changed，状态先于 handlers；配置变化不改状态 | 支持动态子集；不含 static 事件与通用 event metadata record |
| 5.3.3 | Client late READY/ERROR/STALE 回放；ERROR 覆盖 Fatal | 实现子集；API late replay 仅默认 provider；原始事件 payload 不留存，不作历史回放 |
| 1.6.2, 1.7.6 | shutdown 清除 SDK hooks/handlers/global context，closed 不可逆，保留 terminal bindings | 明确差异：非 reset-to-noop；对外 Shutdown 而非 NotReady |
| 1.8.1–2 | Sdk.new 创建独立 providers/context/hooks/handlers 状态 | 实现独立实例入口；同一 Provider 不宜跨 SDK 共享；不据此声称全 API 合规 |
| 6.1.1.1, 6.1.3–4 | track Unit，四层 context 合并，无 tracking provider 时 no-op | 实现；track_checked 为 Result 扩展，不代替标准 Unit 路径 |
| 6.2.1–2 | TrackingEvent 可选 numeric value、自定义 JSON details | JSON 模型支持；constructor 额外拒绝空 key/非有限 value，公开 record 可绕过构造器，provider tracking 边界仍强制 validate |
| static-context 条件要求 | 无 static-context API、RECONCILING/CONTEXT_CHANGED 和异步 reconciliation | 不支持该 paradigm；同步不是 static-context 的同义词 |

## Hooks 的准确解释

before 顺序为 API → Client → Invocation → Provider，各层按注册顺序；after/error/finally 反转整个序列。下一 before 必须观察到前一 before 返回的 overlay。Context 通过不可变接口和复制来保护，before 返回新值而非修改持久 global/client context。

before Err：停止剩余 before、跳过 resolver、进入 error/finally/default。Resolver 失败也进入 error/finally。after Err 停止剩余 after，再 error/finally/default；§4.4.7 只明文规定 before default，after default 是结合 §1.4.10 一般异常要求的实现解释。error/finally 自身的 Result Err 仅记录，不递归触发 error，不阻断其余同阶段 hooks，不替换原结果。finally 的 details 与应用拿到的最终 details 一致。

不能只对 before 已成功执行的 hooks 跑 error/finally；HookPlan 为各 hook 建独立 store。Invalid default 在 client 校验阶段早退，不跑 hooks；此早退及 panic 情况未覆盖为无条件 finally 保证。Hints 使用 EvaluationContext 承载且被复制；它不是 HookData，不能当作阶段间可变 store。

## Lifecycle / events 的规范差异

1. **初始化失败状态来源：**§2.8.1–3 与 §5.3.5 以 provider events 为状态来源。有 initialize callback 时，callback 应在结束前自行 emit_ready/emit_error。当前返回 Err 会调用 record_error 改变 Error/Fatal，但不广播 ERROR。对不发事件的错误 callback，状态与 handlers 会不一致；这是本实现防御性行为的差异，不是规范授予的事件替代机制。成功 Ok 不补 READY。
2. **Shutdown：**§1.7.6 要求 shutdown 结束后为 NOT_READY；当前公开 ProviderStatus::Shutdown/name SHUTDOWN 为终态扩展。§1.6.2 要求 reset 全部 API 状态；当前保留 terminal bindings、对象永久 closed，需创建新 Sdk，不是规范 reset-to-noop 行为。局部 Client context/hooks 也不因此清空。
3. **晚注册回放：**Client 只对当前对应状态执行新 callback，配置通知不重放。Sdk.on 即时回放只检查默认 provider，不涵盖所有 named provider 状态；回放构造的是状态通知，不重建原始 error/message/flags payload。
4. **同步模型：**没有等待异步 initialize 结束及 lifecycle event 已处理的通用 set-and-wait。§1.1.2.4 是 SHOULD；不能把普通同步 setter 包装为通用 async wait。无初始化 callback 的 provider 按 §2.8.5.1 例外自动 Ready。
5. **有界分发：**EventBus 单次 drain 超过 1024 个事件会丢弃剩余；panic 不捕获。此防护意味着不能无条件承诺所有恶意/无限重入事件和 handlers 都执行。

CONFIGURATION_CHANGED 不改变状态。NotReady/Fatal/Shutdown 禁止 resolver，Error/Stale 允许 resolver，是此 SDK 的策略；不能把允许/禁止范围错误归因为规范对所有状态的统一短路要求。

## Tracking 与传播

规范 §6.1.3 的合并链仅为 global → transaction → client → invocation，**不包含 before**。当前 track 不运行 evaluation hooks，不记住上一次 flag key/value，也不自动带上它的 before overlay。要关联业务主体，显式传 context 或在持久 global/client 中提供；此 SDK 没有隐式 transaction carrier。

Client.track 的 callback Err 进入 diagnostics；track_checked 将 Result 返回调用者，是本地扩展。Provider 不实现 tracking 则 no-op；provider callback 自身的网络/flush/送达语义不由 SDK保证。Tracking experimental 标记不是把本章 MUST 自动改成 MAY。

## 验证证据与发布前检查

本地已有 `hooks_test.mbt` 的顺序、overlay 中断、observer Err、HookData 隔离测试；`provider_test.mbt` 的显式 READY、初始化 Err、终态、共享 callback 快照测试；`events_test.mbt` 的过滤、listener 失败、重入上限测试。另有 typed value、context/JSON、metadata、options、resolution、tracking model 的测试源码。它们是本地独立测试，不是官方 suite 运行证明。

发布前应运行实际 check/test 并保存结果，补验 Sdk/Client 集成：late callbacks、domain 替换/共享 retire、domain-scoped 拒绝、shutdown 不可逆、track/track_checked diagnostics、finally 返回 details 一致。文档工作不执行生成接口、格式化或测试以避免与并行实现冲突，也不宣称这些命令已通过。

规范许可不等于符合性背书；Apache-2.0、独立重写或相邻项目查重结论均不能替代上述差异披露。
