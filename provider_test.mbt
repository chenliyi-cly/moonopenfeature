///|
fn provider_test_adapter() -> @moonopenfeature.Provider {
  @moonopenfeature.Provider::new("test", (_, _, default, _) => {
    @moonopenfeature.Resolution::success(default)
  })
}

///|
fn provider_test_context() -> @moonopenfeature.EvaluationContext {
  @moonopenfeature.EvaluationContext::empty()
}

///|
test "provider absent initializer readies exactly once and gates before initialization" {
  let calls = Ref(0)
  let provider = @moonopenfeature.Provider::new("plain", (_, _, _, _) => {
    calls.val += 1
    @moonopenfeature.Resolution::success(Boolean(true))
  })
  let events : Array[String] = []
  let _ = provider
    .events()
    .on(event => {
      try! assert_eq(event.provider_name, "plain")
      events.push(event.event_type.name())
      Ok(())
    })
  try! assert_eq(provider.name(), "plain")
  try! assert_true(provider.status() == NotReady)
  try! assert_true(!provider.is_initialized())
  let blocked = provider.resolve(
    "flag",
    Boolean,
    Boolean(false),
    provider_test_context(),
  )
  try! assert_true(blocked.error is Some({ code: ProviderNotReady, .. }))
  try! assert_true(blocked.value.as_boolean() == Some(false))
  try! assert_eq(calls.val, 0)
  try! assert_true(provider.initialize(provider_test_context()) is Ok(_))
  try! assert_true(provider.initialize(provider_test_context()) is Ok(_))
  provider.emit_ready()
  try! assert_true(provider.is_initialized())
  try! assert_true(provider.status() == Ready)
  try! assert_eq(events, ["PROVIDER_READY"])
  try! assert_true(
    provider.resolve("flag", Boolean, Boolean(false), provider_test_context()).value.as_boolean() ==
    Some(true),
  )
  try! assert_eq(calls.val, 1)
}

///|
test "provider successful manual initializer is not an implicit ready event" {
  let calls = Ref(0)
  let provider = @moonopenfeature.Provider::new(
    "manual",
    (_, _, default, _) => @moonopenfeature.Resolution::success(default),
    initialize=Some((self, context) => {
      calls.val += 1
      try! assert_true(self.is_initialized())
      try! assert_true(context.targeting_key() == Some("user"))
      try! assert_true(self.initialize(context) is Ok(_))
      Ok(())
    }),
  )
  let events : Array[String] = []
  let _ = provider
    .events()
    .on(event => {
      events.push(event.event_type.name())
      Ok(())
    })
  let context = provider_test_context().with_targeting_key("user")
  try! assert_true(provider.initialize(context) is Ok(_))
  try! assert_true(provider.initialize(context) is Ok(_))
  try! assert_eq(calls.val, 1)
  try! assert_true(provider.status() == NotReady)
  try! assert_eq(events.length(), 0)
  provider.emit_ready()
  try! assert_true(provider.status() == Ready)
  try! assert_eq(events, ["PROVIDER_READY"])
}

///|
test "provider callback can emit Ready synchronously with initialized guard set" {
  let provider = @moonopenfeature.Provider::new(
    "ready",
    (_, _, default, _) => @moonopenfeature.Resolution::success(default),
    initialize=Some((self, _) => {
      self.emit_ready()
      Ok(())
    }),
  )
  let count = Ref(0)
  let _ = provider
    .events()
    .on(_ => {
      count.val += 1
      try! assert_true(provider.status() == Ready)
      try! assert_true(provider.is_initialized())
      try! assert_true(provider.initialize(provider_test_context()) is Ok(_))
      Ok(())
    })
  try! assert_true(provider.initialize(provider_test_context()) is Ok(_))
  try! assert_eq(count.val, 1)
}

///|
test "provider initializer errors change status without synthetic events or retries" {
  for code in [@moonopenfeature.ErrorCode::General, ProviderFatal] {
    let calls = Ref(0)
    let error = @moonopenfeature.SdkError::new(code, "initialize failed")
    let provider = @moonopenfeature.Provider::new(
      "failure",
      (_, _, default, _) => @moonopenfeature.Resolution::success(default),
      initialize=Some((_, _) => {
        calls.val += 1
        Err(error)
      }),
    )
    let events : Array[String] = []
    let _ = provider
      .events()
      .on(event => {
        events.push(event.event_type.name())
        Ok(())
      })
    try! assert_true(
      provider.initialize(provider_test_context()) is Err(actual) &&
      actual == error,
    )
    try! assert_true(provider.is_initialized())
    try! assert_true(
      provider.status() == (if code == ProviderFatal { Fatal } else { Error }),
    )
    try! assert_eq(events.length(), 0)
    try! assert_true(provider.initialize(provider_test_context()) is Ok(_))
    try! assert_eq(calls.val, 1)
    provider.emit_ready()
    try! assert_true(
      provider.status() == (if code == ProviderFatal { Fatal } else { Ready }),
    )
    try! assert_eq(events.length(), if code == ProviderFatal { 0 } else { 1 })
  }
}

///|
test "provider initializer explicitly emitted events are not duplicated on error return" {
  let failure = @moonopenfeature.SdkError::new(General, "failed")
  let provider = @moonopenfeature.Provider::new(
    "manual-failure",
    (_, _, default, _) => @moonopenfeature.Resolution::success(default),
    initialize=Some((self, _) => {
      self.emit_ready()
      self.emit_error(failure)
      Err(failure)
    }),
  )
  let seen : Array[String] = []
  let _ = provider
    .events()
    .on(event => {
      seen.push(event.event_type.name())
      Ok(())
    })
  try! assert_true(provider.initialize(provider_test_context()) is Err(_))
  try! assert_eq(seen, ["PROVIDER_READY", "PROVIDER_ERROR"])
  try! assert_true(provider.status() == Error)
}

///|
test "provider resolver executes in Ready Stale Error but not Fatal Shutdown" {
  let calls = Ref(0)
  let provider = @moonopenfeature.Provider::new("gates", (_, _, _, _) => {
    calls.val += 1
    @moonopenfeature.Resolution::success(Integer(7L), reason="STATIC")
  })
  let context = provider_test_context()
  let early = provider.resolve("n", Integer, Integer(1L), context)
  try! assert_true(early.error is Some({ code: ProviderNotReady, .. }))
  provider.initialize(context) |> ignore
  for state in [@moonopenfeature.ProviderStatus::Ready, Stale, Error] {
    match state {
      Ready => ()
      Stale => provider.emit_stale("cache old")
      Error =>
        provider.emit_error(
          @moonopenfeature.SdkError::new(General, "retryable"),
        )
      _ => ()
    }
    let result = provider.resolve("n", Integer, Integer(1L), context)
    try! assert_true(result.error == None)
    try! assert_true(result.value.as_integer() == Some(7L))
    try! assert_eq(result.reason, "STATIC")
  }
  try! assert_eq(calls.val, 3)
  provider.emit_error(@moonopenfeature.SdkError::new(ProviderFatal, "fatal"))
  let fatal = provider.resolve("n", Integer, Integer(1L), context)
  try! assert_true(fatal.error is Some({ code: ProviderFatal, .. }))
  try! assert_true(fatal.value.as_integer() == Some(1L))
  provider.shutdown() |> ignore
  let stopped = provider.resolve("n", Integer, Integer(1L), context)
  try! assert_true(stopped.error is Some({ code: ProviderNotReady, .. }))
  try! assert_eq(calls.val, 3)
}

///|
test "provider lifecycle event payloads and terminal state transitions" {
  let provider = provider_test_adapter()
  let events : Array[@moonopenfeature.ProviderEvent] = []
  let _ = provider
    .events()
    .on(event => {
      events.push(event)
      Ok(())
    })
  provider.initialize(provider_test_context()) |> ignore
  provider.emit_stale("outdated")
  let flags = ["a", "b"]
  provider.emit_configuration_changed(flags)
  flags.clear()
  provider.emit_error(@moonopenfeature.SdkError::new(General, "recoverable"))
  provider.emit_ready()
  provider.emit_error(@moonopenfeature.SdkError::new(ProviderFatal, "terminal"))
  provider.emit_ready()
  provider.emit_stale("must not recover")
  provider.emit_error(@moonopenfeature.SdkError::new(General, "still fatal"))
  try! assert_true(provider.status() == Fatal)
  try! assert_eq(events.map(event => event.event_type.name()), [
    "PROVIDER_READY", "PROVIDER_STALE", "PROVIDER_CONFIGURATION_CHANGED", "PROVIDER_ERROR",
    "PROVIDER_READY", "PROVIDER_ERROR", "PROVIDER_ERROR",
  ])
  try! assert_eq(events[1].message, "outdated")
  try! assert_eq(events[2].flags, ["a", "b"])
  try! assert_true(
    events[3].error is Some({ code: General, message: "recoverable", }),
  )
  try! assert_true(events[5].error is Some({ code: ProviderFatal, .. }))
  for event in events {
    try! assert_eq(event.provider_name, "test")
    try! assert_true(event.domain == None)
  }
  provider.shutdown() |> ignore
  provider.emit_ready()
  provider.emit_stale("late")
  provider.emit_error(@moonopenfeature.SdkError::new(General, "late"))
  provider.emit_configuration_changed(["late"])
  try! assert_true(provider.status() == Shutdown)
  try! assert_eq(events.length(), 7)
}

///|
test "provider shutdown commits state before reentrant callback and is idempotent on failure" {
  let calls = Ref(0)
  let failure = @moonopenfeature.SdkError::new(General, "shutdown failed")
  let provider = @moonopenfeature.Provider::new(
    "shutdown",
    (_, _, default, _) => @moonopenfeature.Resolution::success(default),
    shutdown=Some(self => {
      calls.val += 1
      try! assert_true(self.status() == Shutdown)
      try! assert_true(self.shutdown() is Ok(_))
      try! assert_true(
        self.initialize(provider_test_context())
        is Err({ code: ProviderNotReady, .. }),
      )
      self.emit_ready()
      Err(failure)
    }),
  )
  let events : Array[String] = []
  let _ = provider
    .events()
    .on(event => {
      events.push(event.event_type.name())
      Ok(())
    })
  try! assert_true(provider.shutdown() is Err(actual) && actual == failure)
  try! assert_true(provider.shutdown() is Ok(_))
  try! assert_true(provider.status() == Shutdown)
  try! assert_true(!provider.is_initialized())
  try! assert_eq(calls.val, 1)
  try! assert_eq(events.length(), 0)
}

///|
test "provider terminal state inside initializer survives its return" {
  for fatal in [true, false] {
    let provider = @moonopenfeature.Provider::new(
      "terminal",
      (_, _, default, _) => @moonopenfeature.Resolution::success(default),
      initialize=Some((self, _) => {
        if fatal {
          self.emit_error(
            @moonopenfeature.SdkError::new(ProviderFatal, "terminal"),
          )
        } else {
          self.shutdown() |> ignore
        }
        Err(@moonopenfeature.SdkError::new(General, "late result"))
      }),
    )
    try! assert_true(provider.initialize(provider_test_context()) is Err(_))
    provider.emit_ready()
    try! assert_true(
      provider.status() == (if fatal { Fatal } else { Shutdown }),
    )
  }
}

///|
test "provider preinitialization fatal never calls initializer" {
  let calls = Ref(0)
  let provider = @moonopenfeature.Provider::new(
    "fatal-first",
    (_, _, default, _) => @moonopenfeature.Resolution::success(default),
    initialize=Some((_, _) => {
      calls.val += 1
      Ok(())
    }),
  )
  provider.emit_error(@moonopenfeature.SdkError::new(ProviderFatal, "fatal"))
  try! assert_true(
    provider.initialize(provider_test_context())
    is Err({ code: ProviderFatal, .. }),
  )
  try! assert_true(!provider.is_initialized())
  try! assert_eq(calls.val, 0)
}

///|
test "provider resolver arguments checked results and context isolation" {
  let context = provider_test_context()
    .with_attribute("nested", Json::array([Json::string("original")]))
    .unwrap()
  let provider = @moonopenfeature.Provider::new("validation", (
    key,
    kind,
    default,
    received,
  ) => {
    try! assert_eq(key, "flag")
    try! assert_true(kind == Boolean)
    try! assert_true(default.as_boolean() == Some(false))
    guard received.get("nested") is Some(Array(items)) else {
      try! fail("context missing")
    }
    items.clear()
    @moonopenfeature.Resolution::success(String("wrong type"))
  })
  provider.initialize(context) |> ignore
  let result = provider.resolve("flag", Boolean, Boolean(false), context)
  try! assert_true(result.error is Some({ code: TypeMismatch, .. }))
  try! assert_true(result.value.as_boolean() == Some(false))
  try! assert_eq(result.reason, "ERROR")
  try! assert_true(
    context.get("nested") == Some(Json::array([Json::string("original")])),
  )
}

///|
test "provider resolution validates nonfinite values and preserves callback errors" {
  let provider = @moonopenfeature.Provider::new("invalid", (_, _, _, _) => {
    @moonopenfeature.Resolution::success(Float(1.0 / 0.0))
  })
  provider.initialize(provider_test_context()) |> ignore
  let result = provider.resolve("f", Float, Float(2.0), provider_test_context())
  try! assert_true(result.error is Some({ code: TypeMismatch, .. }))
  try! assert_true(result.value.as_float() == Some(2.0))
  let failure = @moonopenfeature.SdkError::new(FlagNotFound, "missing")
  let failing = @moonopenfeature.Provider::new("missing", (_, _, _, _) => {
    @moonopenfeature.Resolution::failure(Boolean(true), failure)
  })
  failing.initialize(provider_test_context()) |> ignore
  let result = failing.resolve(
    "b",
    Boolean,
    Boolean(false),
    provider_test_context(),
  )
  try! assert_true(result.error == Some(failure))
  try! assert_true(result.value.as_boolean() == Some(false))
}

///|
test "provider default and returned structure values are detached snapshots" {
  let original = [Json::string("default")]
  let returned = [Json::string("result")]
  let provider = @moonopenfeature.Provider::new("snapshot", (_, _, default, _) => {
    guard default is Structure(Array(items)) else {
      try! fail("expected structure")
    }
    items.clear()
    @moonopenfeature.Resolution::success(
      Structure(Json::array(returned)),
      variant=Some("v1"),
    )
  })
  provider.initialize(provider_test_context()) |> ignore
  let result = provider.resolve(
    "s",
    Structure,
    Structure(Json::array(original)),
    provider_test_context(),
  )
  try! assert_eq(original.length(), 1)
  returned.clear()
  try! assert_true(
    result.value.as_structure() == Some(Json::array([Json::string("result")])),
  )
  try! assert_true(result.variant == Some("v1"))
  provider.shutdown() |> ignore
  let blocked = provider.resolve(
    "s",
    Structure,
    Structure(Json::array(original)),
    provider_test_context(),
  )
  original.clear()
  try! assert_true(
    blocked.value.as_structure() == Some(Json::array([Json::string("default")])),
  )
}

///|
test "provider optional tracking and context callbacks are noops" {
  let provider = provider_test_adapter()
  let event = @moonopenfeature.TrackingEvent::new("click").unwrap()
  try! assert_true(provider.track(event, provider_test_context()) is Ok(_))
  try! assert_true(
    provider.on_context_changed(
      provider_test_context(),
      provider_test_context(),
    )
    is Ok(_),
  )
  try! assert_true(provider.status() == NotReady)
  try! assert_true(!provider.is_initialized())
}

///|
test "provider tracking delegates snapshots and propagates errors without lifecycle effects" {
  let failure = @moonopenfeature.SdkError::new(General, "tracking failed")
  let calls = Ref(0)
  let details = provider_test_context()
    .with_attribute("items", Json::array([Json::string("detail")]))
    .unwrap()
  let context = provider_test_context()
    .with_targeting_key("user")
    .with_attribute("items", Json::array([Json::string("context")]))
    .unwrap()
  let event = @moonopenfeature.TrackingEvent::new(
    "click",
    value=Some(3.5),
    details~,
  ).unwrap()
  let provider = @moonopenfeature.Provider::new(
    "track",
    (_, _, default, _) => @moonopenfeature.Resolution::success(default),
    track=Some((received, current) => {
      calls.val += 1
      try! assert_eq(received.key, "click")
      try! assert_true(received.value == Some(3.5))
      try! assert_true(current.targeting_key() == Some("user"))
      guard received.details.get("items") is Some(Array(items)) else {
        try! fail("details missing")
      }
      items.clear()
      guard current.get("items") is Some(Array(attrs)) else {
        try! fail("context missing")
      }
      attrs.clear()
      Err(failure)
    }),
  )
  try! assert_true(
    provider.track(event, context) is Err(actual) && actual == failure,
  )
  try! assert_eq(calls.val, 1)
  try! assert_true(provider.status() == NotReady)
  try! assert_true(
    event.details.get("items") == Some(Json::array([Json::string("detail")])),
  )
  try! assert_true(
    context.get("items") == Some(Json::array([Json::string("context")])),
  )
}

///|
test "provider context change callback receives old new and may explicitly emit events" {
  let failure = @moonopenfeature.SdkError::new(General, "context failed")
  let old = provider_test_context()
    .with_targeting_key("old")
    .with_attribute("items", Json::array([Json::null()]))
    .unwrap()
  let new = old.with_targeting_key("new")
  let calls = Ref(0)
  let provider = @moonopenfeature.Provider::new(
    "context",
    (_, _, default, _) => @moonopenfeature.Resolution::success(default),
    context_changed=Some((self, before, after) => {
      calls.val += 1
      try! assert_eq(self.name(), "context")
      try! assert_true(before.targeting_key() == Some("old"))
      try! assert_true(after.targeting_key() == Some("new"))
      guard before.get("items") is Some(Array(items)) else {
        try! fail("missing old")
      }
      items.clear()
      try! assert_true(after.get("items") == Some(Json::array([Json::null()])))
      self.emit_stale("context changed")
      Err(failure)
    }),
  )
  let messages : Array[String] = []
  let _ = provider
    .events()
    .on(event => {
      messages.push(event.message)
      Ok(())
    })
  try! assert_true(
    provider.on_context_changed(old, new) is Err(actual) && actual == failure,
  )
  try! assert_eq(calls.val, 1)
  try! assert_true(provider.status() == Stale)
  try! assert_eq(messages, ["context changed"])
  try! assert_true(old.get("items") == Some(Json::array([Json::null()])))
  try! assert_true(new.get("items") == Some(Json::array([Json::null()])))
}

///|
test "provider hooks are ordered independent registration snapshots" {
  let provider = provider_test_adapter()
  try! assert_eq(provider.hooks().length(), 0)
  provider.add_hook(@moonopenfeature.Hook::new("first"))
  let snapshot = provider.hooks()
  provider.add_hook(@moonopenfeature.Hook::new("second"))
  try! assert_eq(snapshot.map(hook => hook.name()), ["first"])
  snapshot.clear()
  snapshot.push(@moonopenfeature.Hook::new("outsider"))
  try! assert_eq(provider.hooks().map(hook => hook.name()), ["first", "second"])
}

///|
test "provider event bus shared handle and ordered reentrant recovery" {
  let provider = provider_test_adapter()
  let seen : Array[String] = []
  let first_bus = provider.events()
  let second_bus = provider.events()
  let id = first_bus.on(event => {
    seen.push(event.event_type.name())
    if event.event_type == ProviderError {
      provider.emit_ready()
    }
    Ok(())
  })
  try! assert_eq(second_bus.listener_count(), 1)
  provider.emit_error(@moonopenfeature.SdkError::new(General, "recover"))
  try! assert_eq(seen, ["PROVIDER_ERROR", "PROVIDER_READY"])
  try! assert_true(provider.status() == Ready)
  try! assert_true(second_bus.off(id))
  try! assert_eq(first_bus.listener_count(), 0)
}

///|
test "provider checked resolution preserves success and failure metadata snapshots" {
  let metadata = @moonopenfeature.FlagMetadata::from_values({
    "source": Json::string("cache"),
  }).unwrap()
  let failure = @moonopenfeature.SdkError::new(ParseError, "bad payload")
  for failed in [false, true] {
    let provider = @moonopenfeature.Provider::new("metadata", (_, _, _, _) => {
      let resolution : @moonopenfeature.Resolution = {
        value: Boolean(true),
        reason: "VENDOR_REASON",
        variant: Some("blue"),
        error: if failed {
          Some(failure)
        } else {
          None
        },
        metadata,
      }
      resolution
    })
    provider.initialize(provider_test_context()) |> ignore
    let result = provider.resolve(
      "b",
      Boolean,
      Boolean(false),
      provider_test_context(),
    )
    assert_true(result.metadata.get("source") == Some(Json::string("cache")))
    let exported = result.metadata.values()
    exported.clear()
    assert_true(metadata.get("source") == Some(Json::string("cache")))
    assert_true(result.metadata.get("source") == Some(Json::string("cache")))
    if failed {
      assert_true(result.error == Some(failure))
      assert_true(result.variant == None)
      assert_eq(result.reason, "ERROR")
      assert_true(result.value.as_boolean() == Some(false))
    } else {
      assert_true(result.error == None)
      assert_true(result.variant == Some("blue"))
      assert_eq(result.reason, "VENDOR_REASON")
      assert_true(result.value.as_boolean() == Some(true))
    }
  }
}
