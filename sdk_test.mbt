///|
test "domain handles are live and last binding owns shutdown" {
  let sdk = @moonopenfeature.Sdk::new()
  let a = sdk.client(domain="a")
  let b = sdk.client(domain="b")
  let fallback = sdk.client(domain="unbound")
  try! assert_eq(a.boolean_value("flag", false), false)
  let shutdowns = Ref(0)
  let shared = @moonopenfeature.Provider::new("shared", (_, _, _, _) => @moonopenfeature.Resolution::success(Boolean(true)),
    shutdown=Some(_ => { shutdowns.val += 1; Ok(()) }))
  sdk.set_provider(shared, domain="a").unwrap()
  sdk.set_provider(shared, domain="b").unwrap()
  try! assert_eq(a.boolean_value("flag", false), true)
  try! assert_eq(b.boolean_value("flag", false), true)
  try! assert_eq(fallback.boolean_value("flag", false), false)
  sdk.clear_domain("a").unwrap()
  try! assert_eq(shutdowns.val, 0)
  try! assert_eq(a.boolean_value("flag", false), false)
  sdk.clear_domain("b").unwrap()
  try! assert_eq(shutdowns.val, 1)
  try! assert_true(shared.status() == Shutdown)
  try! assert_true(sdk.set_provider(shared) is Err(_))
  try! assert_true(sdk.clear_domain("") is Err(_))
}

///|
test "provider first domain is visible before initialization and scoped binding rejects reuse" {
  let sdk = @moonopenfeature.Sdk::new()
  let seen : Ref[String?] = Ref(None)
  let provider = @moonopenfeature.Provider::new("scoped", (_, _, d, _) => @moonopenfeature.Resolution::success(d),
    domain_scoped=true,
    initialize=Some((p, _) => { seen.val = p.binding_domain(); p.emit_ready(); Ok(()) }))
  sdk.set_provider(provider, domain="orders").unwrap()
  try! assert_eq(seen.val, Some("orders"))
  try! assert_true(provider.is_domain_scoped())
  try! assert_true(sdk.set_provider(provider, domain="billing") is Err(_))
  try! assert_eq(sdk.registered_domains(), ["", "orders"])
  try! assert_true(provider.status() == Ready)
}

///|
test "API receives once while related clients receive routed events" {
  let sdk = @moonopenfeature.Sdk::new()
  let a = sdk.client(domain="a")
  let b = sdk.client(domain="b")
  let unrelated = sdk.client(domain="other")
  let provider = @moonopenfeature.Provider::new("shared", (_, _, d, _) => @moonopenfeature.Resolution::success(d))
  sdk.set_provider(provider, domain="a").unwrap()
  sdk.set_provider(provider, domain="b").unwrap()
  let api_count = Ref(0)
  let client_count = Ref(0)
  let unrelated_count = Ref(0)
  sdk.on(ProviderConfigurationChanged, _ => { api_count.val += 1; Ok(()) }) |> ignore
  a.on(ProviderConfigurationChanged, e => {
    try! assert_eq(e.domain, Some("a")); client_count.val += 1; Ok(())
  }) |> ignore
  b.on(ProviderConfigurationChanged, e => {
    try! assert_eq(e.domain, Some("b")); client_count.val += 1; Ok(())
  }) |> ignore
  unrelated.on(ProviderConfigurationChanged, _ => { unrelated_count.val += 1; Ok(()) }) |> ignore
  provider.emit_configuration_changed(["checkout"])
  try! assert_eq(api_count.val, 1)
  try! assert_eq(client_count.val, 2)
  try! assert_eq(unrelated_count.val, 0)
}

///|
test "late handlers observe current state not historical configuration events" {
  let sdk = @moonopenfeature.Sdk::new()
  let client = sdk.client()
  let provider = @moonopenfeature.Provider::new("states", (_, _, d, _) => @moonopenfeature.Resolution::success(d))
  sdk.set_provider(provider).unwrap()
  let events : Array[String] = []
  client.on(ProviderReady, _ => { events.push("ready"); Ok(()) }) |> ignore
  provider.emit_stale("old")
  client.on(ProviderStale, _ => { events.push("stale"); Ok(()) }) |> ignore
  provider.emit_error(@moonopenfeature.SdkError::new(General, "temporary"))
  let error_id = client.on(ProviderError, _ => { events.push("error"); Ok(()) })
  provider.emit_configuration_changed(["x"])
  client.on(ProviderConfigurationChanged, _ => { events.push("configuration"); Ok(()) }) |> ignore
  try! assert_eq(events, ["ready", "stale", "error"])
  try! assert_true(client.off(error_id))
  try! assert_true(!client.off(error_id))
  provider.emit_ready()
  try! assert_eq(events, ["ready", "stale", "error", "ready"])
}

///|
test "context notification snapshots and lifecycle mutations are guarded" {
  let sdk = @moonopenfeature.Sdk::new()
  let calls = Ref(0)
  let provider = @moonopenfeature.Provider::new("observer", (_, _, d, _) => @moonopenfeature.Resolution::success(d),
    context_changed=Some((_, old, fresh) => {
      calls.val += 1
      try! assert_eq(old.get("v"), None)
      try! assert_eq(fresh.get("v"), Some(Json::string("new")))
      try! assert_true(sdk.clear_domain("a") is Err(_))
      Err(@moonopenfeature.SdkError::new(General, "observer failure"))
    }))
  sdk.set_provider(provider, domain="a").unwrap()
  sdk.set_provider(provider, domain="b").unwrap()
  let context = @moonopenfeature.EvaluationContext::empty().with_attribute("v", Json::string("new")).unwrap()
  try! assert_true(sdk.set_context(context) is Err(_))
  try! assert_eq(calls.val, 1)
  try! assert_eq(sdk.context().get("v"), Some(Json::string("new")))
  try! assert_eq(sdk.take_diagnostics().length(), 1)
  try! assert_eq(sdk.take_diagnostics().length(), 0)
}

///|
test "shutdown is terminal resets SDK state and calls each provider once" {
  let sdk = @moonopenfeature.Sdk::new()
  let calls = Ref(0)
  let provider = @moonopenfeature.Provider::new("shutdown", (_, _, d, _) => @moonopenfeature.Resolution::success(d),
    shutdown=Some(_ => { calls.val += 1; Err(@moonopenfeature.SdkError::new(General, "cleanup failed")) }))
  sdk.set_provider(provider, domain="a").unwrap()
  sdk.set_provider(provider, domain="b").unwrap()
  sdk.add_hook(@moonopenfeature.Hook::new("api"))
  sdk.set_context(@moonopenfeature.EvaluationContext::empty().with_targeting_key("user")).unwrap()
  let client = sdk.client(domain="a")
  client.on(ProviderReady, _ => Ok(())) |> ignore
  try! assert_true(sdk.shutdown() is Err(_))
  try! assert_eq(calls.val, 1)
  try! assert_true(sdk.is_closed())
  try! assert_eq(sdk.hooks().length(), 0)
  try! assert_eq(sdk.events().listener_count(), 0)
  try! assert_eq(sdk.context().targeting_key(), None)
  try! assert_true(client.boolean_details("x", false).details.error is Some({ code: ProviderNotReady, .. }))
  sdk.shutdown().unwrap()
  try! assert_eq(calls.val, 1)
  try! assert_true(sdk.set_context(@moonopenfeature.EvaluationContext::empty()) is Err(_))
  try! assert_true(sdk.set_provider(@moonopenfeature.Provider::new("new", (_, _, d, _) => @moonopenfeature.Resolution::success(d))) is Err(_))
}
