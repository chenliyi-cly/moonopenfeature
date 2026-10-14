///|
fn require(condition : Bool, message : String) -> Unit {
  if !condition {
    abort(message)
  }
}

///|
/// The SDK routes calls; the injected adapter owns the flag decisions.
fn label_provider(
  name : String,
  label : String,
  retired : Array[String],
) -> @feature.Provider {
  @feature.Provider::new(
    name,
    (key, _, default, _) => {
      if key == "checkout-theme" {
        @feature.Resolution::success(
          @feature.FlagValue::String(label),
          reason="STATIC",
          variant=Some(label),
        )
      } else {
        @feature.Resolution::failure(
          default,
          @feature.SdkError::new(FlagNotFound, "unknown flag: " + key),
        )
      }
    },
    shutdown=Some(provider => {
      retired.push(provider.name())
      println("shutdown: " + provider.name())
      Ok(())
    }),
  )
}

///|
fn show_routes(
  stage : String,
  alpha : @feature.Client,
  beta : @feature.Client,
  guest : @feature.Client,
) -> Unit {
  println(
    stage +
    ": alpha=" +
    alpha.string_value("checkout-theme", "safe") +
    " beta=" +
    beta.string_value("checkout-theme", "safe") +
    " guest=" +
    guest.string_value("checkout-theme", "safe"),
  )
}

///|
fn main {
  let sdk = @feature.Sdk::new()
  let retired : Array[String] = []
  // Construct clients once: their domain bindings are resolved on every call.
  let alpha = sdk.client(domain="tenant-alpha", name="checkout")
  let beta = sdk.client(domain="tenant-beta", name="checkout")
  let guest = sdk.client(domain="guest", name="checkout")
  let default_v1 = label_provider("default-v1", "classic", retired)
  sdk.set_provider(default_v1).unwrap()
  let shared = label_provider("enterprise-shared", "enterprise", retired)
  sdk.set_provider(shared, domain="tenant-alpha").unwrap()
  sdk.set_provider(shared, domain="tenant-beta").unwrap()
  require(
    sdk.registered_domains().length() == 3,
    "guest must not create a provider binding",
  )
  show_routes("initial", alpha, beta, guest)
  require(
    alpha.string_value("checkout-theme", "safe") == "enterprise",
    "alpha binding",
  )
  require(
    beta.string_value("checkout-theme", "safe") == "enterprise",
    "beta binding",
  )
  require(
    guest.string_value("checkout-theme", "safe") == "classic",
    "unbound domain fallback",
  )

  let ready_events : Array[String] = []
  let listener = alpha.on(ProviderReady, event => {
    let line = event.provider_name + "@" + event.domain.unwrap()
    ready_events.push(line)
    println("alpha ready: " + line)
    Ok(())
  })
  let dedicated = label_provider("alpha-v2", "modern", retired)
  sdk.set_provider(dedicated, domain="tenant-alpha").unwrap()
  show_routes("replace alpha", alpha, beta, guest)
  require(
    alpha.string_value("checkout-theme", "safe") == "modern",
    "live client replacement",
  )
  require(
    beta.string_value("checkout-theme", "safe") == "enterprise",
    "other domain isolation",
  )
  require(
    shared.status() == @feature.ProviderStatus::Ready,
    "shared provider retired too early",
  )
  require(retired.length() == 0, "still-bound shared provider must stay alive")

  sdk.clear_domain("tenant-beta").unwrap()
  show_routes("clear beta", alpha, beta, guest)
  require(
    shared.status() == @feature.ProviderStatus::Shutdown,
    "last shared binding must retire",
  )
  require(retired == ["enterprise-shared"], "shared shutdown must run once")
  require(
    beta.string_value("checkout-theme", "safe") == "classic",
    "cleared domain fallback",
  )

  let default_v2 = label_provider("default-v2", "accessible", retired)
  sdk.set_provider(default_v2).unwrap()
  show_routes("replace default", alpha, beta, guest)
  require(
    alpha.string_value("checkout-theme", "safe") == "modern",
    "explicit binding must survive",
  )
  require(
    beta.string_value("checkout-theme", "safe") == "accessible",
    "fallback client stays live",
  )
  require(
    guest.string_value("checkout-theme", "safe") == "accessible",
    "guest follows new default",
  )
  require(
    default_v1.status() == @feature.ProviderStatus::Shutdown,
    "old default must retire",
  )

  sdk.clear_domain("tenant-alpha").unwrap()
  show_routes("clear alpha", alpha, beta, guest)
  require(
    alpha.string_value("checkout-theme", "safe") == "accessible",
    "alpha returns to default",
  )
  require(
    dedicated.status() == @feature.ProviderStatus::Shutdown,
    "dedicated provider retired",
  )
  require(
    ready_events == ["enterprise-shared@tenant-alpha", "alpha-v2@tenant-alpha"],
    "ready replay and replacement notification",
  )
  require(alpha.off(listener), "listener removal")
  sdk.shutdown().unwrap()
  sdk.shutdown().unwrap()
  require(
    retired == ["enterprise-shared", "default-v1", "alpha-v2", "default-v2"],
    "one shutdown per provider",
  )
  let stopped = guest.string_details("checkout-theme", "safe")
  require(
    stopped.value == "safe" &&
    stopped.details.error is Some({ code: ProviderNotReady, .. }),
    "closed SDK must return default",
  )
  println("after shutdown: " + stopped.details.to_json().stringify())
  require(
    sdk.take_diagnostics().length() == 0,
    "unexpected lifecycle diagnostics",
  )
}
