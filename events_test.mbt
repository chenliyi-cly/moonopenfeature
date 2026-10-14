///|
test "events filter by type and domain, preserve order, and remove listeners" {
  let bus = @moonopenfeature.EventBus::new()
  let seen : Array[String] = []
  let id = bus.on(event => {
    seen.push(event.provider_name)
    Ok(())
  })
  let _ = bus.on(
    _ => {
      seen.push("tenant")
      Ok(())
    },
    domain=Some("tenant"),
  )
  let _ = bus.on(
    _ => {
      seen.push("ready")
      Ok(())
    },
    event_type=Some(ProviderReady),
  )
  bus.emit(
    @moonopenfeature.ProviderEvent::new(
      ProviderReady,
      "one",
      domain=Some("tenant"),
    ),
  )
  assert_eq(seen, ["one", "tenant", "ready"])
  assert_true(bus.off(id))
  assert_true(!bus.off(id))
  bus.emit(@moonopenfeature.ProviderEvent::new(ProviderError, "two"))
  assert_eq(seen.length(), 3)
  assert_eq(bus.listener_count(), 2)
  bus.clear()
  assert_eq(bus.listener_count(), 0)
}

///|
test "listener failure does not stop later handlers and flags are copied" {
  let bus = @moonopenfeature.EventBus::new()
  let seen : Array[String] = []
  let _ = bus.on(event => {
    event.flags.push("mutated")
    Err(@moonopenfeature.SdkError::new(General, "observer failure"))
  })
  let _ = bus.on(event => {
    seen.push(event.flags.join(","))
    Ok(())
  })
  let input = ["flag"]
  bus.emit(
    @moonopenfeature.ProviderEvent::new(
      ProviderConfigurationChanged,
      "p",
      flags=input,
    ),
  )
  assert_eq(input, ["flag"])
  assert_eq(seen, ["flag"])
  assert_eq(bus.take_diagnostics().length(), 1)
  assert_eq(bus.take_diagnostics().length(), 0)
}

///|
test "reentrant events are queued and recursive loops are bounded" {
  let bus = @moonopenfeature.EventBus::new()
  let count = Ref(0)
  let _ = bus.on(event => {
    count.val += 1
    bus.emit(event)
    Ok(())
  })
  bus.emit(@moonopenfeature.ProviderEvent::new(ProviderReady, "p"))
  assert_eq(count.val, 1024)
  assert_eq(bus.take_diagnostics().length(), 1)
}
