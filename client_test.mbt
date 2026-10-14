///|
fn test_context(value : String) -> @moonopenfeature.EvaluationContext {
  @moonopenfeature.EvaluationContext::empty()
  .with_attribute("scope", Json::string(value))
  .unwrap()
  .with_targeting_key(value)
}

///|
test "context precedence reaches provider and before overlay remains local" {
  let sdk = @moonopenfeature.Sdk::new()
  let client = sdk.client(name="cart", version="1")
  sdk.set_context(test_context("api")).unwrap()
  client.set_context(test_context("client"))
  let seen : Array[String] = []
  let provider = @moonopenfeature.Provider::new("contexts", (_, _, d, c) => {
    seen.push(c.targeting_key().unwrap())
    try! assert_eq(c.get("scope"), Some(Json::string("hook")))
    @moonopenfeature.Resolution::success(d)
  })
  sdk.set_provider(provider).unwrap()
  client.add_hook(
    @moonopenfeature.Hook::new("overlay", before=(ctx, _) => {
      try! assert_eq(ctx.evaluation_context.targeting_key(), Some("invocation"))
      try! assert_eq(ctx.client.name, "cart")
      Ok(Some(test_context("hook")))
    }),
  )
  let options = @moonopenfeature.EvaluationOptions::new(
    context=test_context("invocation"),
    transaction_context=test_context("transaction"),
  )
  try! assert_eq(client.boolean_value("x", true, options~), true)
  try! assert_eq(seen, ["hook"])
  try! assert_eq(sdk.context().targeting_key(), Some("api"))
  try! assert_eq(client.context().targeting_key(), Some("client"))
  try! assert_eq(options.context().targeting_key(), Some("invocation"))
}

///|
test "all typed results return exact provider type or caller default" {
  let sdk = @moonopenfeature.Sdk::new()
  let provider = @moonopenfeature.Provider::new("typed", (key, _, _, _) => {
    match key {
      "bool" =>
        @moonopenfeature.Resolution::success(
          Boolean(true),
          reason="STATIC",
          variant=Some("on"),
        )
      "int" =>
        @moonopenfeature.Resolution::success(Integer(9223372036854775807L))
      "float" => @moonopenfeature.Resolution::success(Float(2.5))
      "text" => @moonopenfeature.Resolution::success(String("welcome"))
      "json" =>
        @moonopenfeature.Resolution::success(
          Structure(Json::object({ "enabled": Json::boolean(true) })),
        )
      _ =>
        @moonopenfeature.Resolution::failure(
          Boolean(true),
          @moonopenfeature.SdkError::new(FlagNotFound, "missing"),
        )
    }
  })
  sdk.set_provider(provider).unwrap()
  let client = sdk.client()
  try! assert_eq(client.boolean_value("bool", false), true)
  try! assert_eq(client.integer_value("int", 0L), 9223372036854775807L)
  try! assert_eq(client.float_value("float", 0.0), 2.5)
  try! assert_eq(client.string_value("text", "default"), "welcome")
  try! assert_eq(
    client.structure_value("json", Json::null()).stringify(),
    "{\"enabled\":true}",
  )
  let mismatch = client.integer_details("float", 19L)
  try! assert_eq(mismatch.value, 19L)
  try! assert_true(mismatch.details.error is Some({ code: TypeMismatch, .. }))
  let missing = client.string_details("missing", "fallback")
  try! assert_eq(missing.value, "fallback")
  try! assert_eq(missing.details.reason, "ERROR")
  try! assert_true(missing.is_error())
  let successful = client.boolean_details("bool", false)
  try! assert_eq(successful.details.variant, Some("on"))
  try! assert_eq(successful.details.reason, "STATIC")
}

///|
test "before and after failures use default while observers cannot change result" {
  let sdk = @moonopenfeature.Sdk::new()
  let calls = Ref(0)
  sdk
  .set_provider(
    @moonopenfeature.Provider::new("counter", (_, _, _, _) => {
      calls.val += 1
      @moonopenfeature.Resolution::success(Boolean(true))
    }),
  )
  .unwrap()
  let client = sdk.client()
  let final_values : Array[Bool] = []
  let observer = @moonopenfeature.Hook::new(
    "observer",
    error=(_, _, _) => {
      Err(@moonopenfeature.SdkError::new(General, "error observer"))
    },
    on_finally=(_, details, _) => {
      final_values.push(details.value.as_boolean().unwrap())
      Err(@moonopenfeature.SdkError::new(General, "finally observer"))
    },
  )
  client.add_hook(observer)
  client.add_hook(
    @moonopenfeature.Hook::new("fail-before", before=(_, _) => {
      Err(@moonopenfeature.SdkError::new(InvalidContext, "before"))
    }),
  )
  try! assert_eq(client.boolean_value("x", false), false)
  try! assert_eq(calls.val, 0)
  try! assert_eq(sdk.take_diagnostics().length(), 2)
  client.clear_hooks()
  client.add_hook(observer)
  client.add_hook(
    @moonopenfeature.Hook::new("fail-after", after=(_, _, _) => {
      Err(@moonopenfeature.SdkError::new(General, "after"))
    }),
  )
  try! assert_eq(client.boolean_value("x", false), false)
  try! assert_eq(calls.val, 1)
  try! assert_eq(final_values, [false, false])
  try! assert_eq(sdk.take_diagnostics().length(), 2)
}

///|
test "evaluation freezes hook list before callbacks register new hooks" {
  let sdk = @moonopenfeature.Sdk::new()
  let client = sdk.client()
  let calls = Ref(0)
  let late = @moonopenfeature.Hook::new("late", before=(_, _) => {
    calls.val += 1
    Ok(None)
  })
  client.add_hook(
    @moonopenfeature.Hook::new("register", before=(_, _) => {
      client.add_hook(late)
      Ok(None)
    }),
  )
  client.boolean_value("x", false) |> ignore
  try! assert_eq(calls.val, 0)
  client.boolean_value("x", false) |> ignore
  try! assert_eq(calls.val, 1)
}

///|
test "tracking uses context layers but not evaluation hooks and errors are diagnostics" {
  let sdk = @moonopenfeature.Sdk::new()
  let client = sdk.client()
  sdk.set_context(test_context("api")).unwrap()
  client.set_context(test_context("client"))
  let seen : Array[String] = []
  sdk
  .set_provider(
    @moonopenfeature.Provider::new(
      "tracking",
      (_, _, d, _) => @moonopenfeature.Resolution::success(d),
      track=Some((event, ctx) => {
        try! assert_eq(event.key, "purchase")
        try! assert_eq(event.value, Some(0.0))
        seen.push(ctx.targeting_key().unwrap())
        Err(@moonopenfeature.SdkError::new(General, "delivery failed"))
      }),
    ),
  )
  .unwrap()
  let hooks = Ref(0)
  client.add_hook(
    @moonopenfeature.Hook::new("not tracking", before=(_, _) => {
      hooks.val += 1
      Ok(None)
    }),
  )
  let event = @moonopenfeature.TrackingEvent::new("purchase", value=Some(0.0)).unwrap()
  client.track(
    event,
    context=test_context("invocation"),
    transaction_context=test_context("transaction"),
  )
  try! assert_eq(hooks.val, 0)
  try! assert_eq(seen, ["invocation"])
  try! assert_eq(sdk.take_diagnostics().length(), 1)
  try! assert_true(client.track_checked(event) is Err(_))
  try! assert_eq(seen, ["invocation", "client"])
  sdk.shutdown().unwrap()
  client.track(event)
  try! assert_eq(seen.length(), 2)
  try! assert_eq(sdk.take_diagnostics().length(), 1)
}

///|
test "raw tracking construction cannot bypass validation at callback boundary" {
  let sdk = @moonopenfeature.Sdk::new()
  let client = sdk.client()
  let calls = Ref(0)
  sdk
  .set_provider(
    @moonopenfeature.Provider::new(
      "tracking",
      (_, _, d, _) => @moonopenfeature.Resolution::success(d),
      track=Some((_, _) => {
        calls.val += 1
        Ok(())
      }),
    ),
  )
  .unwrap()
  let bad : @moonopenfeature.TrackingEvent = {
    key: "",
    value: None,
    details: @moonopenfeature.EvaluationContext::empty(),
  }
  client.track(bad)
  try! assert_eq(calls.val, 0)
  try! assert_eq(sdk.take_diagnostics().length(), 1)
  let nonfinite : @moonopenfeature.TrackingEvent = {
    key: "event",
    value: Some(1.0 / 0.0),
    details: @moonopenfeature.EvaluationContext::empty(),
  }
  try! assert_true(client.track_checked(nonfinite) is Err(_))
  try! assert_eq(calls.val, 0)
}
