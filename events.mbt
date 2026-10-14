///|
pub(all) enum EventType {
  ProviderReady
  ProviderError
  ProviderStale
  ProviderConfigurationChanged
} derive(Eq)

///|
pub extend EventType with Eq::{equal, not_equal}

///|
pub fn EventType::name(self : EventType) -> String {
  match self {
    ProviderReady => "PROVIDER_READY"
    ProviderError => "PROVIDER_ERROR"
    ProviderStale => "PROVIDER_STALE"
    ProviderConfigurationChanged => "PROVIDER_CONFIGURATION_CHANGED"
  }
}

///|
pub(all) struct ProviderEvent {
  event_type : EventType
  provider_name : String
  domain : String?
  message : String
  error : SdkError?
  flags : Array[String]
}

///|
pub fn ProviderEvent::new(
  event_type : EventType,
  provider_name : String,
  domain~ : String? = None,
  message~ : String = "",
  error~ : SdkError? = None,
  flags~ : Array[String] = [],
) -> ProviderEvent {
  { event_type, provider_name, domain, message, error, flags: flags.copy(), }
}

///|
pub fn ProviderEvent::copy(self : ProviderEvent) -> ProviderEvent {
  { ..self, flags: self.flags.copy(), }
}

///|
struct EventListener {
  internal : Bool
  event_type : EventType?
  domain : String?
  callback : (ProviderEvent) -> Result[Unit, SdkError]
}

///|
/// A synchronous, ordered event bus. Listener snapshots make changes in callbacks
/// effective for the next event, not partway through the current dispatch.
pub struct EventBus {
  priv mut next_id : Int32
  priv listeners : Map[Int32, EventListener]
  priv mut dispatching : Bool
  priv pending : Array[ProviderEvent]
  priv diagnostics : Array[SdkError]
}

///|
pub fn EventBus::new() -> EventBus {
  {
    next_id: 1,
    listeners: Map([]),
    dispatching: false,
    pending: [],
    diagnostics: [],
  }
}

///|
pub fn EventBus::on(
  self : EventBus,
  callback : (ProviderEvent) -> Result[Unit, SdkError],
  event_type~ : EventType? = None,
  domain~ : String? = None,
) -> Int32 {
  let id = self.next_id
  self.next_id += 1
  self.listeners[id] = { internal: false, event_type, domain, callback, }
  id
}

///|
pub fn EventBus::off(self : EventBus, id : Int32) -> Bool {
  let found = self.listeners.contains(id)
  self.listeners.remove(id)
  found
}

///|
pub fn EventBus::listener_count(self : EventBus) -> Int32 {
  self.listeners.length()
}

///|
pub fn EventBus::clear(self : EventBus) -> Unit {
  self.listeners.clear()
}

///|
pub fn EventBus::emit(self : EventBus, event : ProviderEvent) -> Unit {
  self.pending.push(event.copy())
  if self.dispatching {
    return
  }
  self.dispatching = true
  let mut processed = 0
  while self.pending.length() > 0 && processed < 1024 {
    let current = self.pending.remove(0)
    let ids = self.listeners.keys().to_array()
    ids.sort()
    let snapshot : Array[EventListener] = []
    // SDK ownership routing runs before application observers, even those
    // registered before binding. Ordinary observers retain registration order.
    for internal in [true, false] {
      for id in ids {
        match self.listeners.get(id) {
          Some(listener) =>
            if listener.internal == internal {
              snapshot.push(listener)
            }
          None => ()
        }
      }
    }
    for listener in snapshot {
      let type_matches = match listener.event_type {
        None => true
        Some(t) => t == current.event_type
      }
      let domain_matches = match listener.domain {
        None => true
        Some(d) => current.domain == Some(d)
      }
      if type_matches && domain_matches {
        match (listener.callback)(current.copy()) {
          Ok(_) => ()
          Err(error) => self.record_diagnostic(error)
        }
      }
    }
    processed += 1
  }
  if self.pending.length() > 0 {
    self.pending.clear()
    self.record_diagnostic(
      SdkError::new(General, "reentrant event dispatch limit reached"),
    )
  }
  self.dispatching = false
}

///|
fn EventBus::record_diagnostic(self : EventBus, error : SdkError) -> Unit {
  if self.diagnostics.length() == 128 {
    self.diagnostics.remove(0) |> ignore
  }
  self.diagnostics.push(error)
}

///|
pub fn EventBus::take_diagnostics(self : EventBus) -> Array[SdkError] {
  let result = self.diagnostics.copy()
  self.diagnostics.clear()
  result
}

///|
/// Only events corresponding to the current state receive immediate delivery.
/// Configuration changes are notifications, not a replayable lifecycle state.
pub fn EventType::matches_status(
  self : EventType,
  status : ProviderStatus,
) -> Bool {
  match (self, status) {
    (ProviderReady, Ready)
    | (ProviderError, Error | Fatal)
    | (ProviderStale, Stale) => true
    _ => false
  }
}

///|
/// Package-private subscription for ownership routing, never application work.
fn EventBus::on_internal(
  self : EventBus,
  callback : (ProviderEvent) -> Result[Unit, SdkError],
) -> Int32 {
  let id = self.on(callback)
  self.listeners[id] = { ..self.listeners[id], internal: true, }
  id
}
