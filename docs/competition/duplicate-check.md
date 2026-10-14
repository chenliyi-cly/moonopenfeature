# MoonOpenFeature 语义查重与选题记录

- 复核日期：2026-10-13（Asia/Shanghai）
- 项目方向：OpenFeature v0.9 provider-neutral SDK 的 MoonBit 独立实现；不是 flag/rollout 规则引擎。
- 注册表复核基线：`references/project-registry.md` SHA-256 `6BDFA15C47A7B5288680F45C12B48CCF259F5FD886A9F69B84CABAE44409B50A`（3510 行；追加前还会重新检查，以避免覆盖并发更新）。
- 范围说明：沿用本线程此前完成的 MoonCakes、`moon search`、MoonBit GitHub 和相邻项目 README/API/源码/测试检查；本轮重新比对了最新完整注册表的全部项目标题、候选/相关语义项及 2026-10-13 新增条目。未重新打开赛事规则网页。检索关键词按已记录方向归纳，不把本说明冒充逐条 HTTP 请求日志。
- 有限结论：**在已记录检索范围内未发现成熟直接替代**。这不是对所有公开仓库、私有项目或未来新增包的绝对断言。

## 候选方向比较

评分为 1–5；“低重合风险”分数越高表示已记录范围内风险越低。任一候选触发直接重合门禁时，不以总分抵消。

| 排名 | 问题域与候选 | 生态覆盖 / 复用杠杆 / 用户多样性 / 低重合风险 / 实现深度 / 可测试性 / 竞赛可交付 / 可维护性 | 结论与淘汰/推荐依据 |
|---|---|---|---|
| 1 | 标准化应用配置契约：OpenFeature provider-neutral SDK | 5 / 5 / 5 / 3 / 5 / 5 / 4 / 5 | 推荐。服务应用和基础设施库之间的稳定求值/Provider 契约；近邻是 flag engine、rollout planner 和 A/B 分析系统，必须严守“不实现规则引擎”的边界。多语言规范与 Go SDK 提供固定行为基线。 |
| 2 | 分块多维数组存储：Zarr 核心格式 | 5 / 5 / 4 / 1 / 5 / 5 / 3 / 4 | 淘汰。此前检查发现 MoonBit 仓库 `zlhahaha/zarr` 已覆盖核心分块数组能力，独立重写核心存在直接重合；名称或子格式边界不足以构成新项目。版本/commit 未随本轮交接证据保留，不据此作维护状态的绝对判断。 |
| 3 | 身份同步协议：SCIM 核心数据模型与过滤/补丁语义 | 4 / 4 / 4 / 1 / 4 / 5 / 4 / 4 | 淘汰。此前检查发现 MoonSCIM 已直接实现核心协议语义；本轮留存材料未含可确认的仓库 URL/版本，因此不猜测，也不把 URL 缺失当作无重合证据。 |

## OpenFeature 候选能力指纹与边界

- 下游用户：应用/服务作者；实现 Provider 的 SDK/适配器作者；测试、实验与观测基础设施作者。
- 工作流：客户端使用稳定 typed API 请求布尔、数值、字符串或结构化值；SDK 将 client/domain 路由至调用方提供的 Provider；Provider 返回值、原因、错误码、元数据及可选 variant；context、hooks、events、tracking 依规范约束协作。
- 核心数据与约束：evaluation context/attributes、flag key/default/type、resolution details、Provider lifecycle/status、domain、hook stages/errors、tracking event 与标准化错误/metadata。
- 接受范围：按固定 OpenFeature specification v0.9.0（commit `d5b0a734d8cb9b42bf89be2a97c627f58208e811`，Apache-2.0）定义支持矩阵，以官方 Go SDK v1.19.0（commit `5540b6a49436ba4687cfcc530e570caa6d472e40`，Apache-2.0）作行为参考；实现独立编写并保留上游归属，不复制来源不明或不兼容代码。
- 明确不做：本地 flag 规则或 rollout 引擎、实验分流/统计分析、厂商控制面、远程配置拉取、任何特定厂商 Provider/适配器，也不宣称已通过 OpenFeature 官方 conformance suite。
- 三个完整流程：①多租户服务按 domain 选择不同 Provider，对相同 flag key 取得租户隔离的 typed resolution；②CLI/WASM 宿主把自有 Provider 注入 SDK，传入 invocation context 并取得带诊断的默认/解析结果；③实验/观测库经 hooks 观察求值生命周期并由 tracking 上报调用方事件，而不依赖具体 flag 厂商。

## MoonBit 生态相邻项目能力矩阵

下列相邻项目依据本线程此前的 README/API/源码/测试检查记录。能力分类仅针对 OpenFeature 标准 SDK 契约，不按名称相似度判断。

| 项目与证据 | 已检查能力/重合面 | 判定及本项目的禁止越界处 |
|---|---|---|
| MoonFeatureGate (`wccerty/MoonFeatureGate`)，commit `d9c1e8a3d877bac82e9d23875d39bf40952a3ef5` | feature gate / flag 决策与本地规则能力 | 高度相邻。不得在 MoonOpenFeature 加入本地规则解释、策略匹配或 rollout 决策；只实现标准 API、Provider 契约和 SDK 生命周期。 |
| MoonFlagKit (`q0w1ertyuiop/MoonFlagKit`)，commit `e90659ad0a1f8c793cb3290d0bf7190441f06058` | flag 管理/求值能力 | 高度相邻。Provider 可以在别处实现决策；本项目不复制其引擎工作流。 |
| `moonflags` (`WhisperJXH/moonflags`)，commit `b47fd83d4048ca9027fb3f9c01570ca7a04c1c6e` | feature-flag/rollout 相关实现 | 高度相邻；实现边界维持 provider-neutral、符合规范的 API 与返回模型。 |
| CanaryRing (`EJJ-ai-nb/canaryring`)，commit `773034fbc52f88fda72bbe248bcd9fe73d74dea7` | rollout / blast-radius 规划；注册表已有其与 RADIUS codec 不同的记录 | 同方向不同功能。不能把渐进发布计划器并入 SDK。 |
| FlipSpec，commit `8bad754f2243cea2adf18882ebaa8a9d070b7fab` | 此前记录将其列作邻近项目 | repo URL/owner 与版本未在当前证据中确认；不猜测链接或能力细节，也不将该记录视为排除重合的强证据。 |
| `pla678889/moon-experiment` 0.2.3（永久注册表已有） | A/B 测试统计、序贯检验、指标比较和 guardrails | 同方向不同功能：分析实验结果，不实现标准 flag-evaluation/provider SDK。 |
| `QuietlyChan/moonai` 0.1.0（永久注册表已有） | provider-neutral AI SDK | 架构风格相邻，领域数据、求值语义和上游协议不同，不是 OpenFeature 替代品。 |
| `moonbit-community/opentelemetry` 0.1.5（永久注册表已有） | telemetry 协议/SDK | 可作为 hooks/tracking 的消费者或集成邻居；不提供 feature flag evaluation/provider 契约。 |

注册表也逐项复核了截至基线内全部 reserved、completed、rejected、external-checked 项及最新 2026-10-13 追加内容：未见 OpenFeature、provider-neutral feature evaluation 或同一核心工作流的项目指纹。精确字符串不存在本身不作为通过理由；判定还比较了用户、工作流、核心数据、关键协议/API、输出和明确边界。

## 检索范围、限制与记录

- 检索来源：已完成的 `moon search`（扩大结果上限）、MoonCakes 模块/文档检索、GitHub MoonBit 仓库与比赛项目检查、上述近邻仓库 README/API/源码/测试，以及本地永久注册表全量比对。
- 语义检索方向：OpenFeature / feature flag SDK / typed evaluation / resolution details / evaluation context / provider lifecycle / domain / hooks / tracking / standard error model；以及 feature gate、flag engine、rollout、canary、A/B testing、SCIM、Zarr 等替代/边界概念。
- 证据边界：MoonCakes/GitHub 搜索索引及默认分支可能滞后；本轮没有对所有历史提交、未公开仓库或新发布包逐一穷尽。当前交接未保留 MoonFeatureGate 等的版本号，FlipSpec 的 repo URL/owner/version 未确认；这些缺口已显式保留，不填造数据。详细仓库检查结果来自此前检查，未在本轮重开规则网页。
- 保留结论：相关 flag/rollout 项目是必须遵守的高度相邻边界，不因为它们名称不同就视作无关。该实现仅在严格限定为 OpenFeature 标准化 provider-neutral SDK、且不实现决策引擎的范围内继续。

## 最终决策

参赛者已明确选定 OpenFeature provider-neutral MoonBit SDK。以 OpenFeature v0.9.0 specification 和 Go SDK v1.19.0 固定版本为独立行为参考；在 `project-registry.md` 追加 reservation 及尚未登记的相邻项目 `external-checked` 记录后，方可开始实现。若复核并发注册表发现同一能力指纹已被保留，立即停止，不通过改名规避。
## 2026-10-14 implementation gate revalidation

The fixed-commit adjacent source/API/test inspection was repeated using osc2026-guide's Project Research Guide. These are read-only inspection results, not claims that adjacent tests were executed locally.

| Project | Version / branch | Material overlap and substantive boundary |
|---|---|---|
| wccerty/MoonFeatureGate | 0.1.3 / main, d9c1e8a3d877bac82e9d23875d39bf40952a3ef5 | Bool/String/Int/Double evaluations, defaults/reasons, targeting attributes and two-context overlay are implemented. FeatureProvider returns FlagDefinition; eval.mbt executes the rules itself. registry.mbt manages named snapshots, not SDK domain-to-resolution-provider lifecycles. No implemented standard hooks/tracking contract was found in the inspected interface/source/tests. |
| q0w1ertyuiop/MoonFlagKit | 0.2.0 / master, e90659ad0a1f8c793cb3290d0bf7190441f06058 | ConfigProvider.load_flags loads rule definitions; evaluate(Flag,EvalContext) executes rules and buckets. docs/design.md and docs/application.md explicitly plan an OpenFeature-style facade, but the inspected current API/source does not implement it. This future plan is a real adjacent risk, not evidence of no connection. |
| WhisperJXH/moonflags | 0.2.1 / main, b47fd83d4048ca9027fb3f9c01570ca7a04c1c6e | String variant engine with segments, targeting and stable rollout; engine.mbt and moonflags_test.mbt checked. Not a standardized resolution Provider SDK. |
| EJJ-ai-nb/canaryring | 0.1.0 / main, 773034fbc52f88fda72bbe248bcd9fe73d74dea7 | docs/API.md, simulate.mbt and canaryring_test.mbt implement stage/risk simulation and rollout gates, not typed evaluation/provider SDK contracts. |
| yourenA1108/flipspec | 0.1.1 / main, 8bad754f2243cea2adf18882ebaa8a9d070b7fab | The formerly missing identity is confirmed: https://github.com/yourenA1108/flipspec and https://mooncakes.io/docs/yourenA1108/flipspec. planner.mbt and flipspec_test.mbt concern Yes/No/Unknown policies, counterfactual repair and minimality certificates. Its variable-value domains are not SDK provider domains. |

All five fixed commits were confirmed to exist and were the default-branch heads at inspection. Versions were cross-checked against moon.mod and moon search. MoonCakes pages were inspected at /docs/<owner>/<lowercase-package-name>. Repository links above and the original matrix provide fixed source provenance. GitHub search/index limits and private/unpublished work remain outside the bounded verdict. Independence is warranted because existing engines define their own decision models; this SDK instead standardizes caller/provider integration and can wrap those engines in a downstream provider without copying or extending their rule implementations.

Registry revalidation read current capability-matching fingerprints, including this project's existing reservation, MoonStix/MoonRADIUS external catalogues, and existing experiment/AI/telemetry neighbours. The existing MoonOpenFeature reservation belongs to this task. In the recorded scope no competing reservation for the same SDK workflow was found. **在已记录检索范围内未发现成熟直接替代**.

Specification authority: OpenFeature spec v0.9.0 is the normative source. Go SDK v1.19.0 is only a behavior reference: its automatic READY/ERROR synthesis on Init differs from spec §2.8 for providers with initialization callbacks. This difference must not be silently ported or called full v0.9 conformance.