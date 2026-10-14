///|
/// SDK instances are independent. They do not consult process-global configuration.
pub struct Sdk {
  priv bindings : Map[String, Provider]
  priv known_domains : Map[String, Bool]
  priv watched : Array[(Provider, Int)]
  priv bus : EventBus
  priv api_bus : EventBus
  priv hooks : Array[Hook]
  priv mut context : EvaluationContext
  priv diagnostics : Array[SdkError]
  priv mut mutating : Bool
  priv mut closed : Bool
}

///|
pub fn Sdk::new() -> Sdk {
  let sdk : Sdk = {
    bindings: Map([]), known_domains: Map([]), watched: [], bus: EventBus::new(), api_bus: EventBus::new(), hooks: [],
    context: EvaluationContext::empty(), diagnostics: [], mutating: false, closed: false,
  }
  let noop = Provider::new("No-op", (_, _, default, _) => Resolution::success(default, reason="DEFAULT"))
  noop.bind_domain("") |> ignore
  sdk.bindings[""] = noop
  sdk.known_domains[""] = true
  sdk.watch(noop)
  noop.initialize(sdk.context) |> ignore
  sdk
}

///|
pub fn Sdk::is_closed(self : Sdk) -> Bool {
  self.closed
}

///|
pub fn Sdk::provider(self : Sdk, domain? : String = "") -> Provider {
  match self.bindings.get(domain) {
    Some(provider) => provider
    None => self.bindings[""]
  }
}

///|
pub fn Sdk::provider_status(self : Sdk, domain? : String = "") -> ProviderStatus {
  self.provider(domain~).status()
}

///|
pub fn Sdk::registered_domains(self : Sdk) -> Array[String] {
  let result = self.bindings.keys().to_array()
  result.sort()
  result
}

///|
fn Sdk::watch(self : Sdk, provider : Provider) -> Unit {
  for pair in self.watched {
    if physical_equal(pair.0, provider) {
      return
    }
  }
  let id = provider.events().on(event => {
    // Freeze domain ownership before observers can mutate bindings. API
    // callbacks may replace the provider, but cannot erase this event's route.
    let domains = self.known_domains.keys().to_array()
    domains.sort()
    let recipients : Array[String] = []
    for domain in domains {
      if physical_equal(self.provider(domain~), provider) {
        recipients.push(domain)
      }
    }
    self.api_bus.emit(event.copy())
    for domain in recipients {
      self.bus.emit({ ..event.copy(), domain: Some(domain) })
    }
    Ok(())
  })
  self.watched.push((provider, id))
}

///|
fn Sdk::is_bound(self : Sdk, provider : Provider) -> Bool {
  for _, candidate in self.bindings {
    if physical_equal(candidate, provider) {
      return true
    }
  }
  false
}

///|
fn Sdk::retire(self : Sdk, provider : Provider) -> Unit {
  if self.is_bound(provider) {
    return
  }
  let mut index = 0
  while index < self.watched.length() {
    let (candidate, id) = self.watched[index]
    if physical_equal(candidate, provider) {
      provider.events().off(id) |> ignore
      self.watched.remove(index) |> ignore
      break
    }
    index += 1
  }
  match provider.shutdown() {
    Ok(_) => ()
    Err(error) => self.record_diagnostic(error)
  }
}

///|
/// Replacing a domain never shuts down a provider still used by another domain.
/// Failed initialization leaves the new binding's error/not-ready state observable.
pub fn Sdk::set_provider(self : Sdk, provider : Provider, domain? : String = "") -> Result[Unit, SdkError] {
  if self.closed || self.mutating {
    return Err(SdkError::new(General, "SDK is closed or a lifecycle mutation is in progress"))
  }
  if provider.status() == Shutdown {
    return Err(SdkError::new(ProviderNotReady, "a shut down provider cannot be rebound"))
  }
  match provider.bind_domain(domain) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let previous = self.bindings.get(domain)
  if previous is Some(old) && physical_equal(old, provider) {
    return Ok(())
  }
  self.mutating = true
  self.bindings[domain] = provider
  self.known_domains[domain] = true
  self.watch(provider)
  let initialized = provider.initialize(self.context.copy())
  match previous {
    Some(old) => self.retire(old)
    None => ()
  }
  self.mutating = false
  initialized
}

///|
pub fn Sdk::clear_domain(self : Sdk, domain : String) -> Result[Unit, SdkError] {
  if domain == "" {
    return Err(SdkError::new(General, "the default domain cannot be removed"))
  }
  if self.closed || self.mutating {
    return Err(SdkError::new(General, "SDK is closed or a lifecycle mutation is in progress"))
  }
  self.mutating = true
  match self.bindings.get(domain) {
    Some(old) => {
      self.bindings.remove(domain)
      self.retire(old)
    }
    None => ()
  }
  self.mutating = false
  Ok(())
}

///|
pub fn Sdk::context(self : Sdk) -> EvaluationContext {
  self.context.copy()
}

///|
pub fn Sdk::set_context(self : Sdk, context : EvaluationContext) -> Result[Unit, SdkError] {
  if self.closed || self.mutating {
    return Err(SdkError::new(General, "SDK is closed or a lifecycle mutation is in progress"))
  }
  self.mutating = true
  let old = self.context.copy()
  self.context = context.copy()
  let providers = self.watched.copy()
  let mut first_error = None
  for pair in providers {
    match pair.0.on_context_changed(old.copy(), self.context.copy()) {
      Ok(_) => ()
      Err(error) => {
        if first_error == None {
          first_error = Some(error)
        }
        self.record_diagnostic(error)
      }
    }
  }
  self.mutating = false
  match first_error {
    None => Ok(())
    Some(error) => Err(error)
  }
}

///|
pub fn Sdk::add_hook(self : Sdk, hook : Hook) -> Unit {
  self.hooks.push(hook)
}

///|
pub fn Sdk::clear_hooks(self : Sdk) -> Unit {
  self.hooks.clear()
}

///|
pub fn Sdk::hooks(self : Sdk) -> Array[Hook] {
  self.hooks.copy()
}

///|
pub fn Sdk::events(self : Sdk) -> EventBus {
  self.bus
}

///|
fn Sdk::record_diagnostic(self : Sdk, error : SdkError) -> Unit {
  if self.diagnostics.length() == 128 {
    self.diagnostics.remove(0) |> ignore
  }
  self.diagnostics.push(error)
}

///|
pub fn Sdk::take_diagnostics(self : Sdk) -> Array[SdkError] {
  let result = self.diagnostics.copy()
  self.diagnostics.clear()
  for error in self.api_bus.take_diagnostics() {
    result.push(error)
  }
  for error in self.bus.take_diagnostics() {
    result.push(error)
  }
  for pair in self.watched {
    for error in pair.0.events().take_diagnostics() {
      result.push(error)
    }
  }
  result
}

///|
pub fn Sdk::shutdown(self : Sdk) -> Result[Unit, SdkError] {
  if self.closed {
    return Ok(())
  }
  if self.mutating {
    return Err(SdkError::new(General, "a lifecycle mutation is in progress"))
  }
  self.closed = true
  self.mutating = true
  let watched = self.watched.copy()
  self.watched.clear()
  let mut first_error = None
  for pair in watched {
    pair.0.events().off(pair.1) |> ignore
    match pair.0.shutdown() {
      Ok(_) => ()
      Err(error) => {
        if first_error == None {
          first_error = Some(error)
        }
        self.record_diagnostic(error)
      }
    }
  }
  self.hooks.clear()
  self.bus.clear()
  self.api_bus.clear()
  self.context = EvaluationContext::empty()
  self.known_domains.clear()
  // Keep bindings to terminal providers so existing clients fail closed.
  // No resolver can run after the closed flag has been set.
  self.mutating = false
  match first_error {
    None => Ok(())
    Some(error) => Err(error)
  }
}

///|
/// API-wide observers receive each provider event once, unlike the detailed
/// domain fan-out bus returned by events(). Late state replay uses the default
/// provider; configuration notifications are never replayed.
pub fn Sdk::on(
  self : Sdk,
  event_type : EventType,
  callback : (ProviderEvent) -> Result[Unit, SdkError],
) -> Int {
  let id = self.api_bus.on(callback, event_type=Some(event_type))
  let provider = self.provider()
  if !self.closed && event_type.matches_status(provider.status()) {
    match callback(ProviderEvent::new(event_type, provider.name())) {
      Ok(_) => ()
      Err(error) => self.record_diagnostic(error)
    }
  }
  id
}

///|
pub fn Sdk::off(self : Sdk, id : Int) -> Bool {
  self.api_bus.off(id)
}
