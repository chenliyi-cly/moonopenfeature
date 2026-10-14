# MoonOpenFeature

用 MoonBit 实现的可复用、同步、与供应方无关的功能开关 SDK 核心。
应用通过统一接口获取类型化结果、默认值与诊断，并管理上下文、钩子、供应方域和业务事件跟踪，无需在每个调用点绑定某个开关引擎。
**开关决策由供应方（Provider）负责；本 SDK 不是规则引擎。**

版本：`chenliyi-cly/moonopenfeature@0.1.1`。许可证：Apache-2.0。

## 适用场景

- **多租户后端**：为不同域绑定不同的解析供应方，运行时替换某个域的供应方；共享供应方只在最后一个绑定移除后释放。
- **命令行、嵌入式和 WASM 应用**：注入宿主管理的供应方，复用 Boolean、Int64、Double、String、JSON 五类值接口，以及一致的默认值和错误模型。
- **平台与可观测性集成**：通过有序钩子观察开关评估，跟踪业务事件，不自行实现开关规则，也不绑定特定分析厂商。

[三个可运行示例](examples/README.md)提供完整的下游工作流和断言，无需网络服务或凭据配置。

## 安装与使用

安装指定版本：

```sh
moon add chenliyi-cly/moonopenfeature@0.1.1
```

在应用的 `moon.pkg` 中导入根包：

```moonbit
import {
  "chenliyi-cly/moonopenfeature" @feature,
}
```

供应方回调是应用决策与 SDK 之间的集成边界。下面的代码可放入应用入口函数中：

```moonbit
let sdk = @feature.Sdk::new()
let provider = @feature.Provider::new("application", (key, kind, default, context) => {
  if key == "checkout-v2" && kind == Boolean {
    @feature.Resolution::success(Boolean(context.targeting_key() == Some("demo")), reason="STATIC")
  } else {
    @feature.Resolution::failure(default, @feature.SdkError::new(FlagNotFound, "unknown key"))
  }
})
sdk.set_provider(provider).unwrap()
let client = sdk.client(name="checkout", version="1")
client.set_context(@feature.EvaluationContext::empty().with_targeting_key("demo"))
let result = client.boolean_details("checkout-v2", false)
println(result.details.to_json().stringify())
sdk.shutdown().unwrap()
```

示例中的简单决策属于应用注入的供应方，不是 SDK 内置规则模型。
克隆仓库后，在仓库根目录运行三个完整示例：

```sh
moon run examples/multitenant --deny-warn
moon run examples/typed_provider --deny-warn
moon run examples/observability --deny-warn
```

## 公共 API 与数据约束

| API | 约束与行为 |
| --- | --- |
| `FlagValue` / `FlagType` | 五种精确类型，不隐式转换数值；Int64 序列化为 JSON 时保留精确十进制表示 |
| `EvaluationContext` | 经校验的 JSON 属性与可选 targeting key；不可变的按键覆盖，以及深拷贝访问器 |
| `Resolution` / `EvaluationDetails` | 包含 reason、variant、错误和标量 metadata；类型不匹配或供应方失败时返回调用者默认值 |
| `Sdk` / `Client` | SDK 实例相互独立；支持默认供应方回退、显式域绑定，以及共享供应方的生命周期管理 |
| `Hook` / `HookPlan` | before 正序，after/error/finally 逆序；按支持的类型筛选；每个钩子、每次评估使用独立 JSON 暂存数据 |
| `Provider` | 使用 Result 回调与显式生命周期事件；初始化和关闭只执行一次；可选择限制为单域绑定 |
| `TrackingEvent` | 可选有限数值和 JSON 详情；`Client.track` 记录错误而不抛错，`track_checked` 是返回 Result 的扩展接口 |

上下文覆盖优先级由低到高为：**SDK < 显式事务上下文 < 客户端 < 本次调用 < before 钩子**。
before 钩子的覆盖只对当前评估有效。业务事件跟踪只合并前四层上下文，不执行评估钩子。

钩子执行前会冻结本次使用的注册列表和 hints。before 或 after 失败时，继续执行 error 和 finally，并返回默认值。
error/finally 观察者自身的失败只进入诊断，不替换原始结果。
**SDK 不捕获回调 panic**；回调应通过 Result/Resolution 报告预期错误。

## 供应方生命周期与事件

没有初始化回调时，注册操作将供应方置为 Ready。
存在初始化回调时，供应方必须自行发出 Ready/Error 事件；返回 Ok 不会自动产生 Ready。
返回 Err 会防御性地更新错误状态，但不会自动合成事件，这是已记录的规范差异。
Ready/Error/Stale 处理器看到的是更新后的状态；配置变更通知不改变就绪状态。
后注册的状态处理器接收当前状态通知，而非历史配置事件。

客户端是跟随当前域绑定的句柄，不是构造时的供应方快照。
替换供应方不会移除客户端事件处理器，后续评估会使用新供应方。
SDK 在调用用户观察者前冻结事件所属域，避免观察者替换绑定影响当前事件路由。
API 级观察者对每个供应方事件只接收一次通知。
供应方实例可以在**同一个 SDK 内**由多个域共享，但不支持跨 SDK 共享。

## 本地验证与 CI

```sh
moon info
moon fmt --check
python3 scripts/verify.py           # 三个可执行目标的验证，以及 native 静态检查
python3 scripts/verify.py --native  # 同时构建、测试和运行 native，需要本机 C 编译器
```

[CI 工作流](.github/workflows/ci.yml)覆盖接口一致性、格式、严格检查、构建、测试，以及三个示例的运行，目标包括 wasm-gc、wasm、js 和 native。
官方 Linux 工具链及核心库下载的 SHA-256 固定在 `scripts/toolchain-lock.json` 中。
如果官方下载地址中的内容发生变化，校验会失败，必须审查后显式更新锁定信息；滚动下载地址并不等于不可变版本地址。

本地 Windows 使用 moon 0.1.20261012 / moonc v0.10.15+943464bfa，wasm-gc、wasm、js 各通过 **81 项测试**。
native 本地仅完成严格静态检查；其构建、测试和示例运行由 Linux CI 验证，不宣称在缺少 C 编译器的本机执行过。
仓库中的[公共接口文件](pkg.generated.mbti)由工具生成，不手工维护。
更多约束见[架构说明](docs/architecture.md)、[安全边界](docs/security.md)和[规范符合性矩阵](docs/conformance.md)。

## 功能边界与来源

这是参考 OpenFeature Specification v0.9.0 和 Go SDK v1.19.0 独立重写的 MoonBit **同步动态上下文子集**，不是完整符合规范的 SDK，也不是 OpenFeature 官方发行版。
不提供规则/百分比分流、远程传输或配置、认证、厂商适配器、异步生命周期、隐式任务局部事务传播、Datetime 值、静态上下文协调，以及任意类型的钩子数据。
JSON 深度上限为 64，校验边界会拒绝循环结构和非有限数值。
SDK 关闭后不可重新启用；需要重新构造 SDK 才能恢复服务。

[有限范围语义查重记录](docs/competition/duplicate-check.md)包含相邻开关引擎，以及 MoonFlagKit 计划中的 OpenFeature 接口。
**在已记录检索范围内未发现成熟直接替代**，不表示所有公开、私有或未发布项目都已被穷尽检查。
应用可以通过自己的供应方适配已有引擎；本 SDK 不应扩展为这些引擎的重复实现。

## 许可证与归属

- [Apache-2.0 许可证](LICENSE)
- [版权和来源声明](NOTICE)
- [第三方归属与参考边界](THIRD_PARTY.md)
- [AI 辅助使用说明](AI_USAGE.md)
- [更新日志](CHANGELOG.md)

本项目未复制上游实现代码或上游测试夹具。
