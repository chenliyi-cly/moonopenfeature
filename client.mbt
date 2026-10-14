///|
pub struct Client {
  priv sdk : Sdk
  priv metadata : ClientMetadata
  priv mut context : EvaluationContext
  priv hooks : Array[Hook]
}

///|
/// Clients are live domain handles, not snapshots of the provider at construction.
pub fn Sdk::client(self : Sdk, domain? : String = "", name? : String = "", version? : String = "") -> Client {
  self.known_domains[domain] = true
  { sdk: self, metadata: { domain, name, version }, context: EvaluationContext::empty(), hooks: [] }
}

///|
pub fn Client::metadata(self : Client) -> ClientMetadata {
  self.metadata
}

///|
pub fn Client::provider_status(self : Client) -> ProviderStatus {
  self.sdk.provider_status(domain=self.metadata.domain)
}

///|
pub fn Client::context(self : Client) -> EvaluationContext {
  self.context.copy()
}

///|
pub fn Client::set_context(self : Client, context : EvaluationContext) -> Unit {
  self.context = context.copy()
}

///|
pub fn Client::add_hook(self : Client, hook : Hook) -> Unit {
  self.hooks.push(hook)
}

///|
pub fn Client::clear_hooks(self : Client) -> Unit {
  self.hooks.clear()
}

///|
pub fn Client::hooks(self : Client) -> Array[Hook] {
  self.hooks.copy()
}

///|
pub fn Client::on(
  self : Client,
  event_type : EventType,
  callback : (ProviderEvent) -> Result[Unit, SdkError],
) -> Int {
  let id = self.sdk.events().on(callback, event_type=Some(event_type), domain=Some(self.metadata.domain))
  let provider = self.sdk.provider(domain=self.metadata.domain)
  if event_type.matches_status(provider.status()) {
    match callback(ProviderEvent::new(event_type, provider.name(), domain=Some(self.metadata.domain))) {
      Ok(_) => ()
      Err(error) => self.sdk.record_diagnostic(error)
    }
  }
  id
}

///|
pub fn Client::off(self : Client, id : Int) -> Bool {
  self.sdk.events().off(id)
}

///|
pub fn Client::evaluate(
  self : Client,
  key : String,
  default : FlagValue,
  options? : EvaluationOptions = EvaluationOptions::new(),
) -> EvaluationDetails {
  let expected = default.flag_type()
  match default.validate() {
    Err(error) => return EvaluationDetails::from_resolution(key, Resolution::failure(default.copy(), error))
    Ok(_) => ()
  }
  let frozen_default = default.copy()
  let frozen_options = options.copy()
  let provider = self.sdk.provider(domain=self.metadata.domain)
  let merged = self.sdk.context()
    .merge(frozen_options.transaction_context())
    .merge(self.context.copy())
    .merge(frozen_options.context())
  let plan = HookPlan::new(expected, self.sdk.hooks(), self.hooks.copy(), frozen_options.hooks(), provider.hooks())
  let base : HookContext = {
    flag_key: key, flag_type: expected, default_value: frozen_default.copy(),
    evaluation_context: merged, client: self.metadata, provider_name: provider.name(), data: HookData::new(),
  }
  let hints = frozen_options.hints()
  let before = plan.before(base, hints)
  let final_context = base.with_context(before.context)
  let resolution = match before.error {
    Some(error) => Resolution::failure(frozen_default.copy(), error)
    None => {
      if self.sdk.is_closed() {
        Resolution::failure(frozen_default.copy(), SdkError::new(ProviderNotReady, "SDK is shut down"))
      } else {
        provider.resolve(key, expected, frozen_default.copy(), before.context.copy())
      }
    }
  }
  let mut details = EvaluationDetails::from_resolution(key, resolution.checked(expected, frozen_default))
  if details.error == None {
    match plan.after(final_context, details, hints) {
      Ok(_) => ()
      Err(error) => details = EvaluationDetails::from_resolution(key, Resolution::failure(frozen_default.copy(), error))
    }
  }
  match details.error {
    Some(error) => {
      for observer_error in plan.on_error(final_context, error, hints) {
        self.sdk.record_diagnostic(observer_error)
      }
    }
    None => ()
  }
  for observer_error in plan.run_finally(final_context, details, hints) {
    self.sdk.record_diagnostic(observer_error)
  }
  details.copy()
}

///|
pub fn Client::track_checked(
  self : Client,
  event : TrackingEvent,
  context? : EvaluationContext = EvaluationContext::empty(),
  transaction_context? : EvaluationContext = EvaluationContext::empty(),
) -> Result[Unit, SdkError] {
  if self.sdk.is_closed() {
    return Err(SdkError::new(ProviderNotReady, "SDK is shut down"))
  }
  let merged = self.sdk.context().merge(transaction_context).merge(self.context).merge(context)
  self.sdk.provider(domain=self.metadata.domain).track(event.copy(), merged)
}

///|
/// Standard no-throw tracking: optional provider failures are diagnostics, not
/// evaluation failures. Use track_checked when an integration needs a Result.
pub fn Client::track(
  self : Client,
  event : TrackingEvent,
  context? : EvaluationContext = EvaluationContext::empty(),
  transaction_context? : EvaluationContext = EvaluationContext::empty(),
) -> Unit {
  match self.track_checked(event, context~, transaction_context~) {
    Ok(_) => ()
    Err(error) => self.sdk.record_diagnostic(error)
  }
}
