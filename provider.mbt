///|
/// Synchronous callback adapter, not a flag decision engine. Lifecycle events
/// are explicit: an initializer must emit_ready itself, even when it returns Ok.
/// Fields are package-visible but hidden from consumers of the package.
pub struct Provider {
  priv name : String
  priv domain_scoped : Bool
  priv mut first_domain : String?
  priv resolver : (String, FlagType, FlagValue, EvaluationContext) -> Resolution
  priv mut status : ProviderStatus
  priv mut initialized : Bool
  priv mut stopped : Bool
  priv hooks : Array[Hook]
  priv bus : EventBus
  priv initialize_callback : ((Provider, EvaluationContext) -> Result[
    Unit,
    SdkError,
  ])?
  priv shutdown_callback : ((Provider) -> Result[Unit, SdkError])?
  priv track_callback : ((TrackingEvent, EvaluationContext) -> Result[
    Unit,
    SdkError,
  ])?
  priv context_changed_callback : ((
    Provider,
    EvaluationContext,
    EvaluationContext,
  ) -> Result[Unit, SdkError])?
}

///|
pub fn Provider::new(
  name : String,
  resolver : (String, FlagType, FlagValue, EvaluationContext) -> Resolution,
  domain_scoped? : Bool = false,
  initialize? : ((Provider, EvaluationContext) -> Result[Unit, SdkError])? = None,
  shutdown? : ((Provider) -> Result[Unit, SdkError])? = None,
  track? : ((TrackingEvent, EvaluationContext) -> Result[Unit, SdkError])? = None,
  context_changed? : ((Provider, EvaluationContext, EvaluationContext) -> Result[
    Unit,
    SdkError,
  ])? = None,
) -> Provider {
  {
    name,
    domain_scoped,
    first_domain: None,
    resolver,
    status: NotReady,
    initialized: false,
    stopped: false,
    hooks: [],
    bus: EventBus::new(),
    initialize_callback: initialize,
    shutdown_callback: shutdown,
    track_callback: track,
    context_changed_callback: context_changed,
  }
}

///|
pub fn Provider::name(self : Provider) -> String {
  self.name
}

///|
pub fn Provider::status(self : Provider) -> ProviderStatus {
  self.status
}

///|
/// Records an initialization attempt, not readiness or successful completion.
pub fn Provider::is_initialized(self : Provider) -> Bool {
  self.initialized
}

///|
/// At most one attempt, including failed and reentrant attempts. Set the guard
/// before entering user code. Only an absent callback synthesizes Ready.
/// Returned errors update state without inventing an event. Terminal state set
/// inside a callback cannot be undone by its eventual return value.
pub fn Provider::initialize(
  self : Provider,
  context : EvaluationContext,
) -> Result[Unit, SdkError] {
  if self.stopped {
    return Err(SdkError::new(ProviderNotReady, "provider is shut down"))
  }
  if self.initialized {
    return Ok(())
  }
  if self.status == Fatal {
    return Err(SdkError::new(ProviderFatal, "provider is fatal"))
  }
  self.initialized = true
  match self.initialize_callback {
    None => {
      self.emit_ready()
      Ok(())
    }
    Some(callback) => {
      let result = callback(self, context.copy())
      if result is Err(error) {
        self.record_error(error)
      }
      result
    }
  }
}

///|
/// Terminal state is committed before the callback. Reentrant or repeated
/// shutdown is a successful no-op, including after a callback returns Err.
/// There is no invented shutdown event in the OpenFeature event vocabulary.
pub fn Provider::shutdown(self : Provider) -> Result[Unit, SdkError] {
  if self.stopped {
    return Ok(())
  }
  self.stopped = true
  self.status = Shutdown
  match self.shutdown_callback {
    None => Ok(())
    Some(callback) => callback(self)
  }
}

///|
/// Default validation belongs to the caller. The resolver sees snapshots;
/// checked validates its output and detaches mutable values and metadata.
pub fn Provider::resolve(
  self : Provider,
  key : String,
  kind : FlagType,
  default : FlagValue,
  context : EvaluationContext,
) -> Resolution {
  match self.status.evaluation_error() {
    Some(error) => Resolution::failure(default.copy(), error)
    None =>
      (self.resolver)(key, kind, default.copy(), context.copy()).checked(
        kind, default,
      )
  }
}

///|
/// Tracking is an independent optional callback, not flag evaluation: it is
/// not gated on readiness and does not synthesize lifecycle state or events.
pub fn Provider::track(
  self : Provider,
  event : TrackingEvent,
  context : EvaluationContext,
) -> Result[Unit, SdkError] {
  match self.track_callback {
    None => Ok(())
    Some(callback) => callback(event.copy(), context.copy())
  }
}

///|
/// Context notifications likewise leave state/events to the callback. Both
/// contexts are independently snapshotted, even when old and new are identical.
pub fn Provider::on_context_changed(
  self : Provider,
  old : EvaluationContext,
  new : EvaluationContext,
) -> Result[Unit, SdkError] {
  match self.context_changed_callback {
    None => Ok(())
    Some(callback) => callback(self, old.copy(), new.copy())
  }
}

///|
pub fn Provider::add_hook(self : Provider, hook : Hook) -> Unit {
  self.hooks.push(hook)
}

///|
/// The registration list is detached; immutable Hook callbacks are shared.
pub fn Provider::hooks(self : Provider) -> Array[Hook] {
  self.hooks.copy()
}

///|
/// Return the same bus so consumers may register and remove observers.
pub fn Provider::events(self : Provider) -> EventBus {
  self.bus
}

///|
/// Fatal and Shutdown are terminal. Recoverable Error and Stale may become
/// Ready again. Repeated Ready is ignored rather than emitting a duplicate.
pub fn Provider::emit_ready(self : Provider) -> Unit {
  if self.stopped || self.status == Fatal || self.status == Ready {
    return
  }
  self.status = Ready
  self.bus.emit(ProviderEvent::new(ProviderReady, self.name))
}

///|
/// All errors remain observable until shutdown. A later recoverable error
/// cannot downgrade Fatal; returned initializer errors reuse this state logic.
fn Provider::record_error(self : Provider, error : SdkError) -> Unit {
  if self.stopped || self.status == Fatal {
    return
  }
  self.status = if error.code == ProviderFatal { Fatal } else { Error }
}

///|
pub fn Provider::emit_error(self : Provider, error : SdkError) -> Unit {
  if self.stopped {
    return
  }
  self.record_error(error)
  self.bus.emit(
    ProviderEvent::new(
      ProviderError,
      self.name,
      message=error.message,
      error=Some(error),
    ),
  )
}

///|
/// Staleness cannot recover Fatal or Shutdown. Repeat notifications in Stale
/// are allowed so a changed diagnostic message can be delivered.
pub fn Provider::emit_stale(self : Provider, message : String) -> Unit {
  if self.stopped || self.status == Fatal {
    return
  }
  self.status = Stale
  self.bus.emit(ProviderEvent::new(ProviderStale, self.name, message~))
}

///|
/// Configuration notifications do not change readiness. Flags are copied by
/// ProviderEvent and EventBus; shutdown suppresses subsequent notifications.
pub fn Provider::emit_configuration_changed(
  self : Provider,
  flags : Array[String],
) -> Unit {
  if self.stopped {
    return
  }
  self.bus.emit(
    ProviderEvent::new(ProviderConfigurationChanged, self.name, flags~),
  )
}

///|
/// The first SDK binding domain, available to initialize callbacks. Standalone
/// initialization has no SDK domain; binding records it before callbacks run.
pub fn Provider::binding_domain(self : Provider) -> String? {
  self.first_domain
}

///|
pub fn Provider::is_domain_scoped(self : Provider) -> Bool {
  self.domain_scoped
}

///|
fn Provider::bind_domain(self : Provider, domain : String) -> Result[Unit, SdkError] {
  match self.first_domain {
    Some(first) =>
      if self.domain_scoped && first != domain {
        Err(SdkError::new(General, "domain-scoped provider cannot serve multiple domains"))
      } else {
        Ok(())
      }
    None => {
      self.first_domain = Some(domain)
      Ok(())
    }
  }
}
