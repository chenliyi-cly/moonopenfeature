# 第三方来源、许可与独立实现边界

MoonOpenFeature 的根 LICENSE 为 Apache License 2.0；NOTICE 记录固定上游参考。本文件是出处清单，不是法律意见、完整依赖审计或规范认证。当前声明的来源策略是：以规范定义行为、阅读其他 SDK 作为比较参考，在 MoonBit 中独立重写，不复制上游实现代码或第三方测试数据。后续若实际引入代码/fixture，必须重新登记并保留相应许可/notice，不能沿用“不复制”的笼统声明。

## 固定上游

| 来源 | 固定版本与提交 | 使用范围 | 许可证据 |
| --- | --- | --- | --- |
| OpenFeature specification | v0.9.0 / `d5b0a734d8cb9b42bf89be2a97c627f58208e811` | API 术语、typed evaluation、context、hooks、provider/lifecycle/events、tracking 的规范行为参考 | [该提交 LICENSE](https://github.com/open-feature/spec/blob/d5b0a734d8cb9b42bf89be2a97c627f58208e811/LICENSE)，Apache-2.0 |
| OpenFeature Go SDK | v1.19.0 / `5540b6a49436ba4687cfcc530e570caa6d472e40` | 行为/结构比较，不是 Go 代码移植，不作为偏离规范的理由 | [该提交 LICENSE](https://github.com/open-feature/go-sdk/blob/5540b6a49436ba4687cfcc530e570caa6d472e40/LICENSE)，Apache-2.0 |

[固定规范目录](https://github.com/open-feature/spec/tree/d5b0a734d8cb9b42bf89be2a97c627f58208e811/specification)；[固定 Go SDK 源码](https://github.com/open-feature/go-sdk/tree/5540b6a49436ba4687cfcc530e570caa6d472e40)。Apache-2.0 的适用义务应以完整许可文本及实际分发内容判断；引用不表示 OpenFeature 项目对本 SDK 背书。

特别是 Go SDK 参考版本的初始化自动事件处理不能当作 v0.9.0 规范：定义 initialize 的 provider 应自己发 READY/ERROR，SDK 不应凭返回值合成。当前 SDK 的其他已知差异见 [docs/conformance.md](docs/conformance.md)。

## MoonBit 运行时和依赖边界

代码使用 MoonBit 标准库/内建类型（包括 Json、Map、Array、Result），由工具链提供。根 NOTICE 将 MoonBit core 记录为 International Digital Economy Academy 的 Apache-2.0 作品。CI 固定 moon 0.1.20261012 / moonc v0.10.15+943464bfa 及官方工具链/core archive SHA-256（scripts/toolchain-lock.json）；未检查工具链内部完整依赖树，故不宣称完整 SBOM，也不把标准库说成项目自行编写的代码。分发运行时或新增第三方包前，应按实际版本核查其许可和 notices。

## 相邻项目：研究参考，不是依赖或代码来源

以下为已完成语义查重的固定证据；本次文档更新没有重新开展生态检索。它们不作为 vendored implementation、运行依赖或测试 fixture；不从查重行为推定已获得任意代码复用许可。

| 项目 | 固定源码 | 实质边界 |
| --- | --- | --- |
| MoonFeatureGate | [wccerty/MoonFeatureGate @ d9c1e8a3d877bac82e9d23875d39bf40952a3ef5](https://github.com/wccerty/MoonFeatureGate/tree/d9c1e8a3d877bac82e9d23875d39bf40952a3ef5) | typed evaluation/context 有重叠；其 provider 加载定义，由本地规则求值。此 SDK 不扩写该决策引擎。 |
| MoonFlagKit | [q0w1ertyuiop/MoonFlagKit @ e90659ad0a1f8c793cb3290d0bf7190441f06058](https://github.com/q0w1ertyuiop/MoonFlagKit/tree/e90659ad0a1f8c793cb3290d0bf7190441f06058) | 当前主要是规则/分桶；设计文档明确规划未来 OpenFeature-style facade。**这是实际相邻风险，不能表述为没有重叠或以后永不替代。** |
| moonflags | [WhisperJXH/moonflags @ b47fd83d4048ca9027fb3f9c01570ca7a04c1c6e](https://github.com/WhisperJXH/moonflags/tree/b47fd83d4048ca9027fb3f9c01570ca7a04c1c6e) | segments/targeting/rollout 变体引擎，而非标准 provider-neutral SDK。 |
| canaryring | [EJJ-ai-nb/canaryring @ 773034fbc52f88fda72bbe248bcd9fe73d74dea7](https://github.com/EJJ-ai-nb/canaryring/tree/773034fbc52f88fda72bbe248bcd9fe73d74dea7) | 阶段/风险模拟与 rollout gates，不是本 SDK 的 typed provider 合同。 |
| FlipSpec | [yourenA1108/flipspec @ 8bad754f2243cea2adf18882ebaa8a9d070b7fab](https://github.com/yourenA1108/flipspec/tree/8bad754f2243cea2adf18882ebaa8a9d070b7fab) | 已确认真实仓库；三值策略、反事实修复和最小性证明，其变量 domain 不是 provider domain。 |

边界不是名称不同，而是“谁负责决策、谁负责标准化集成”。后续若加入本地规则、rollout planner 或扩展到相邻项目核心能力，应重新做语义比较；这里的固定快照不证明整个公开/私有生态不存在替代。详细已记录证据见 docs/competition/duplicate-check.md。

## 变更时的出处检查

新增源码、示例、测试、配置或生成材料时，记录真实来源、固定版本、许可和修改范围；检查所需版权/NOTICE。不得把 AI 输出作为规避上游出处的中间层。当前文档中的规范摘要为释义，不复制完整规范章节；本地测试是独立编写的验证，不冒称原版官方 suite。
