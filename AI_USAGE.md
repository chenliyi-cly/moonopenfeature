# AI 辅助使用说明

## 已知参与范围

项目使用 AI 辅助进行固定上游语义研究、相邻项目源码/API/测试比较、架构与测试建议，以及 MoonBit 实现协作和文档起草。本次文档任务读取当前源码及测试源码，并编写 architecture、security、conformance、THIRD_PARTY、AI_USAGE、CHANGELOG 六份文档。主线程并行集成实现，因此本文不表示这些文档作者独立核验过每次源码变动。

AI 输出是待审查的工程材料，不是来源、许可、安全或符合性认证。具体模型版本不在此处猜测；也不把未实际运行的工具/测试写成已经完成。

## 参考与重写策略

规范以 OpenFeature spec v0.9.0 的固定提交为权威，Go SDK v1.19.0 仅作行为参考。具体 SHA、Apache-2.0 许可和相邻项目出处见 [THIRD_PARTY.md](THIRD_PARTY.md)。策略是在 MoonBit 中独立重写，不复制上游实现代码或第三方测试数据；不能因由 AI 生成就免除出处与版权检查。

相邻项目 MoonFlagKit 的未来 OpenFeature facade 规划已明确披露，不使用 AI 摘要把真实相邻风险改写成“完全无重叠”。项目仅实现 provider-neutral SDK，不扩展本地规则/rollout 引擎以制造表面差异。

## 必须由维护者复核的内容

- 对照固定规范核查 MUST、SHOULD、条件要求及例外，不能只看 AI 的自然语言结论。
- 检查 callback Result 错误路径与 panic 边界、hook 顺序和每 hook/evaluation 数据隔离、context 复制及覆盖顺序。
- 检查初始化事件来源、late callback、domain 生命周期与不可逆 shutdown，避免把安全扩展描述为规范原文。
- 检查 tracking 的四层 context 合并、Unit diagnostics 与 track_checked 扩展，不能声称自动继承 before overlay。
- 执行实际 check/test 并审阅结果；本次文档工作只读取了测试源码，没有执行或认证完整 suite。
- 检查新增代码/fixture 的真实出处和许可，不作“AI 生成所以无第三方版权”的推断。

## 已披露而非隐藏的限制

JSON-only HookData 不支持任意原生对象；context/hints 无原生 Datetime；没有 async evaluation、自动 transaction propagation 或 static-context reconciliation。公共 callbacks 的预期失败使用 Result/Resolution；panic/abort 不捕获。Shutdown 保留 terminal bindings 且对象不可逆 closed，非规范 reset-to-noop；完整差异见 [docs/conformance.md](docs/conformance.md)。

## 数据与操作边界

本次文档任务不需要账号绑定、联系人、凭据或私有申请材料，不访问这些内容；不操作 registry、Git 或远程仓库。公开文档不得加入私人身份资料、认证材料或私有业务 context。SDK 本身不提供 AI 服务调用或遥测上传；下游 provider/hook 的外部 I/O 属于各自集成责任。

本说明不是完整逐提示日志，也不声称覆盖所有历史协作记录。维护者应随实际使用变化更新其内容，并对最终发布材料的准确性、可解释性、可测试性和可维护性负责。
