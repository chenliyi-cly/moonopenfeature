# Executable downstream examples

These are three independent `is-main` packages in the SDK module. Each imports
`chenliyi-cly/moonopenfeature` explicitly and uses only its public API. They use
in-memory, application-owned callbacks; no credentials, vendor services,
registry access, process-global configuration, or network calls are required.
The SDK routes and validates decisions but does not implement a decision engine.

Each program aborts on a violated invariant. A successful exit therefore checks
the scenario rather than merely printing illustrative text.

## Run from the repository root

```sh
moon run examples/multitenant --deny-warn
moon run examples/typed_provider --deny-warn
moon run examples/observability --deny-warn
```

The module's preferred target is wasm-gc. To check JavaScript portability, append
`--target js` to each command. No root manifest changes, `moon info`, or
whole-module formatting are needed. The `run-output.txt` in each package contains
the captured wasm-gc stdout from the local run; JSON object field order is not
part of the API contract.

## 1. Multitenant domain routing and replacement

`multitenant/main.mbt` creates live clients for two tenants and an unbound guest.
A shared enterprise provider serves both tenants, while the guest uses the
configured default provider. The scenario then:

1. Replaces only alpha's provider without changing either client's identity.
2. Checks the shared provider remains Ready while beta still uses it.
3. Clears beta's binding, returns beta to the default, and checks the shared
   provider shuts down exactly once after its last binding disappears.
4. Replaces the default and verifies fallback clients follow it while alpha's
   dedicated provider remains unaffected.
5. Clears alpha, unsubscribes its ready observer, and shuts down the SDK twice.
   Shutdown callbacks still run once per provider, and a post-shutdown evaluation
   returns its safe default with `PROVIDER_NOT_READY` diagnostics.

The ready observer checks immediate replay for the current provider and the
subsequent replacement notification with the tenant's domain.

## 2. Injected typed provider, context, defaults and diagnostics

`typed_provider/main.mbt` injects a local catalog and a contextual boolean rule.
Its explicit initializer initially leaves the provider NotReady, verifying that
an `Ok` initializer return is not a readiness event and the resolver is not called.
The provider then explicitly emits readiness.

The application evaluates Boolean, Int64, Double, String and structured JSON
flags, retaining metadata and variant diagnostics. The Int64 value
`9007199254740993` remains exact in both the typed result and serialized output.
The callback inspects the effective context and asserts this precedence:

`SDK < transaction < client < invocation`

Nonconflicting attributes survive each merge, and source contexts remain intact.
Missing flags, provider type mismatches and explicit provider parse errors return
the caller's defaults with their original error codes in evaluation details.
Those errors do not become SDK observer diagnostics.

## 3. Hooks, lifecycle events and tracking observability

`observability/main.mbt` installs Boolean hooks at SDK, client, invocation and
provider scopes. It verifies forward before ordering, reverse success/error and
completion ordering, and before-hook context flowing to the resolver. `on_finally`
is the public completion callback name; the client orchestrates `HookPlan` stages.

Every hook uses the same scratch key in `HookContext.data`; assertions establish
per-hook isolation, persistence across stages, and reset for each evaluation.
An invocation observer deliberately returns errors, demonstrating that:

- completion observer failure does not replace a successful value;
- error observer failure does not hide the original missing-flag diagnostic;
- other observers still run, and their errors are available once through
  `Sdk.take_diagnostics()`.

The provider records a purchase payload and the separately merged tracking
context. Assertions check that tracking runs no evaluation hooks and does not
inherit an earlier evaluation's hook-injected cohort. `track_checked` exposes an
analytics transport error as a Result. Standard Unit-returning `track` records
that same failure in SDK diagnostics without throwing. Lifecycle output includes
Ready and ConfigurationChanged events; the event listener is removed before
shutdown.
