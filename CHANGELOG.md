# 更新日志

## 0.1.1 — 2026-10-14

- 将主 README 和三个示例的使用说明完整改为中文，保留公共 API 名称及可运行代码。
- 同步安装说明和包版本，修正 0.1.0 更新日志中已过时的集成阶段描述。
- 本次仅更新文档和版本元数据，不改变核心实现或公共接口；保留已发布的 0.1.0。

## 0.1.0 — 2026-10-14

首个公开版本，已发布 GitHub Release 和 MoonCakes。以下保留首次实现的能力与边界；发布并不表示完整 OpenFeature 规范符合性。

### Added

- Provider-neutral 同步 SDK 核心：Boolean、Int64、Double、String、JSON Structure 的 typed value/details，标准错误/default、开放 reason 与标量 metadata。
- JSON context 的校验、深拷贝、按键覆盖；global、显式 transaction 参数、client、invocation 的合并。
- 四层 hooks：before 正向逐步合并，after/error/finally 逆向；每 hook/evaluation 独立 JSON HookData，阶段间保留。
- 默认/named provider 绑定、live domain client、共享 provider 的 retire 生命周期、domain-scoped bool 选项和 first binding domain 查询。
- 同步 provider events、domain 路由、Result 错误 diagnostics、late READY/ERROR/STALE callbacks；CONFIGURATION_CHANGED 不改变 readiness。
- Client.track Unit/no-op/diagnostics，以及 track_checked Result 扩展；tracking context 不执行或继承 evaluation before hooks。
- 架构、安全边界、符合性差异、第三方出处与 AI 使用说明六份文档；固定 OpenFeature spec/Go SDK 提交与 Apache-2.0 来源。

### Explicit limitations / deviations

- 不声明 full OpenFeature conformance、官方认证、官方 suite 全通过。
- HookData 仅 JSON，不满足任意类型值；context/hints 无原生 Datetime。
- 不支持 async/nonblocking evaluation、自动 transaction propagation 或 static-context reconciliation。显式 transaction 参数不是自动 carrier。
- Callback 的 Result/Resolution 错误可处理；panic、abort 和阻塞 callback 不捕获或隔离。
- 初始化 callback 必须显式发事件；成功返回不补 READY。当前返回 Err 会记录 Error/Fatal 状态而不合成 ERROR，偏离纯事件驱动状态规则。
- SDK shutdown 清除 SDK hooks/handlers/global context，但保留 terminal bindings、不可逆 closed；公开 Shutdown 状态不是规范要求的 NotReady/reset-to-noop。
- API 级 late replay 仅检查默认 provider；事件类型不包含 static reconciliation 事件，未提供通用 event metadata record。事件重入排空和 diagnostics 有本地上限。
- Tracking constructor 的非空 key/有限 value 为本地约束，公开 record 可绕过；不提供后台送达、重试或 exactly-once 保证。
- MoonFlagKit 的未来 OpenFeature facade 规划仍是实际相邻风险；SDK 范围不含本地规则/rollout 引擎。

### Verification boundary

0.1.0 的 Linux CI 已完成 wasm-gc、wasm、js、native 的严格检查、构建、各 81 项测试与三个示例运行。本地 Windows 仅执行前三个目标及 native 静态检查。记录见 https://github.com/chenliyi-cly/moonopenfeature/actions/runs/38513107154 。

### Correctness hardening

- Validate raw tracking records before provider callbacks, not only constructor input.
- Reject invalid numeric JSON representations in scalar metadata while retaining exact integer representations.
- Freeze event ownership before API observers and prioritize internal SDK routing ahead of pre-registered provider observers.
