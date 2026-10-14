# MoonOpenFeature

A reusable, synchronous, provider-neutral feature-flag SDK core in MoonBit.
Applications get typed values, consistent defaults and diagnostics, contexts,
hooks, provider domains and business-event tracking without coupling each call
site to a flag engine. **Providers own decisions; this SDK is not a rule engine.**

Version: `chenliyi-cly/moonopenfeature@0.1.0`. Apache-2.0.

## Who can reuse it?

- Multitenant backend services bind different resolution providers to domains,
  replace one domain at runtime, and retire a shared provider only after its last binding.
- CLI, embedded and WASM applications inject a host-owned provider and consume
  the same Boolean/Int64/Double/String/JSON APIs, defaults and error vocabulary.
- Platform/observability integrations add ordered hooks and track business events
  without implementing flag rules or coupling evaluation to an analytics vendor.

Three complete, assertion-backed workflows are in [examples](examples/README.md).
They require no network service or secret configuration.

## Install / use

```sh
moon add chenliyi-cly/moonopenfeature@0.1.0
```

Import the root package in your `moon.pkg`:

```moonbit
import {
  "chenliyi-cly/moonopenfeature" @feature,
}
```

A provider callback is the integration boundary:

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

The example intentionally injects a tiny application-owned decision, not an SDK
rule model. For executable source packages, clone this repository and run:

```sh
moon run examples/multitenant --deny-warn
moon run examples/typed_provider --deny-warn
moon run examples/observability --deny-warn
```

## Stable core model

| API | Contract |
| --- | --- |
| `FlagValue` / `FlagType` | Five exact types; no numeric coercion; Int64 JSON preserves decimal representation |
| `EvaluationContext` | Validated JSON attributes and optional targeting key; immutable overlays and deep-copy accessors |
| `Resolution` / `EvaluationDetails` | Reason, variant, error, scalar metadata; wrong type or provider failure returns caller default |
| `Sdk` / live `Client` | Independent instances; default fallback and explicit provider domains; shared-instance ownership |
| `Hook` / `HookPlan` | Forward before; reverse after/error/finally; supported-type filtering; per-hook/evaluation JSON scratch data |
| `Provider` | Result callbacks; explicit lifecycle events; once-only initialize/shutdown; optional scoped-domain binding |
| `TrackingEvent` | Optional finite measure and JSON details; `Client.track` records errors without throwing; `track_checked` is a Result extension |

Context precedence is **SDK < explicit transaction < client < invocation < before
hooks**. A before overlay is local to its evaluation. Tracking merges only the
first four layers and does not run evaluation hooks.

Hooks freeze their registration list and hints before invocation. A before/after
failure leads to error then finally and the default. Error/finally observer failures
are diagnostics and do not replace the original result. Callback panics are **not**
caught; callbacks must report expected failures through their Result/Resolution contract.

## Provider lifecycle and events

Without an initializer, registration readies the provider. With an initializer,
it must emit its own Ready/Error event; returning Ok does not synthesize Ready.
Returning Err updates defensive state but does not synthesize an event (a documented
specification difference). Ready/Error/Stale handlers see updated state, while
configuration notifications do not alter readiness. Late state handlers receive
current-state notifications, not historical configuration events.

Clients are live handles: replacing a provider preserves client handlers and
changes subsequent resolution. SDK routing freezes domain ownership before user
observers can replace bindings. API-wide observers receive each event once.
Provider instances may be shared by domains **inside one SDK**, not across SDKs.

## Verification

```sh
moon info
moon fmt --check
python3 scripts/verify.py           # portable execution + native static check
python3 scripts/verify.py --native  # requires a native C compiler
```

The CI workflow performs strict interface/format/check/build/test and all three
examples for wasm-gc, wasm, JS and native. Official Linux toolchain/core downloads
are SHA-256 locked in `scripts/toolchain-lock.json`: changed rolling URLs fail
closed until the lock is deliberately reviewed. Do not mistake a rolling URL for
an immutable version archive.

Local verification on Windows with moon 0.1.20261012 / moonc v0.10.15+943464bfa:
**81 tests**; native static checking is supported, but native build/test execution
requires a C compiler and is verified by CI rather than claimed as local execution.
The checked-in [interface](pkg.generated.mbti) is generated, not hand-maintained.
See [architecture](docs/architecture.md), [security](docs/security.md) and
[conformance matrix](docs/conformance.md) for limits and ownership details.

## Boundaries / provenance

This is an independent MoonBit rewrite of a **synchronous dynamic-context subset**
referencing OpenFeature spec v0.9.0 and Go SDK v1.19.0, not a full-conformance SDK
or an official OpenFeature distribution. It does not supply rules/rollouts, remote
transport/configuration, authentication, vendor adapters, asynchronous lifecycle,
implicit task-local transaction propagation, Datetime values, static-context
reconciliation or arbitrary-type hook data. JSON depth is bounded at 64;
cyclic/non-finite data is rejected at validated boundaries. SDK shutdown is
terminal and requires constructing a new SDK to restart.

The source-level comparison includes adjacent flag engines and MoonFlagKit's
planned OpenFeature facade: [scoped duplicate review](docs/competition/duplicate-check.md).
**在已记录检索范围内未发现成熟直接替代** is a bounded finding, not an exclusivity claim.
The SDK can integrate an existing engine through application-owned providers;
it must not grow into a duplicate of that engine.

[LICENSE](LICENSE), [NOTICE](NOTICE), [third-party attribution](THIRD_PARTY.md),
[AI assistance](AI_USAGE.md), [changelog](CHANGELOG.md).
No upstream implementation or upstream test fixtures were copied.
