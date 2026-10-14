///|
pub(all) struct ClientMetadata {
  name : String
  version : String
  domain : String
}

///|
pub(all) struct HookContext {
  flag_key : String
  flag_type : FlagType
  default_value : FlagValue
  evaluation_context : EvaluationContext
  client : ClientMetadata
  provider_name : String
  data : HookData
}

///|
pub fn HookContext::copy(self : HookContext) -> HookContext {
  { ..self, default_value: self.default_value.copy(), evaluation_context: self.evaluation_context.copy() }
}

///|
pub fn HookContext::with_context(self : HookContext, context : EvaluationContext) -> HookContext {
  { ..self, default_value: self.default_value.copy(), evaluation_context: context.copy() }
}

///|
/// Hook callbacks return errors explicitly. Exceptions/panics from user callbacks
/// are not caught; integrations must use this Result contract.
pub struct Hook {
  priv name : String
  priv types : Array[FlagType]?
  priv before : (HookContext, EvaluationContext) -> Result[EvaluationContext?, SdkError]
  priv after : (HookContext, EvaluationDetails, EvaluationContext) -> Result[Unit, SdkError]
  priv error : (HookContext, SdkError, EvaluationContext) -> Result[Unit, SdkError]
  priv on_finally : (HookContext, EvaluationDetails, EvaluationContext) -> Result[Unit, SdkError]
}

///|
pub fn Hook::new(
  name : String,
  types? : Array[FlagType]? = None,
  before? : (HookContext, EvaluationContext) -> Result[EvaluationContext?, SdkError] = (_, _) => Ok(None),
  after? : (HookContext, EvaluationDetails, EvaluationContext) -> Result[Unit, SdkError] = (_, _, _) => Ok(()),
  error? : (HookContext, SdkError, EvaluationContext) -> Result[Unit, SdkError] = (_, _, _) => Ok(()),
  on_finally? : (HookContext, EvaluationDetails, EvaluationContext) -> Result[Unit, SdkError] = (_, _, _) => Ok(()),
) -> Hook {
  { name, types: types.map(ts => ts.copy()), before, after, error, on_finally }
}

///|
pub fn Hook::name(self : Hook) -> String {
  self.name
}

///|
pub fn Hook::supports(self : Hook, kind : FlagType) -> Bool {
  match self.types {
    None => true
    Some(types) => types.contains(kind)
  }
}

///|
/// An invocation freezes its hooks before any user callbacks execute.
pub struct HookPlan {
  priv hooks : Array[Hook]
  priv data : Array[HookData]
}

///|
pub fn HookPlan::new(
  kind : FlagType,
  api : Array[Hook],
  client : Array[Hook],
  invocation : Array[Hook],
  provider : Array[Hook],
) -> HookPlan {
  let hooks = []
  for scope in [api, client, invocation, provider] {
    for hook in scope {
      if hook.supports(kind) {
        hooks.push(hook)
      }
    }
  }
  { hooks, data: hooks.map(_ => HookData::new()) }
}

///|
pub fn HookPlan::names(self : HookPlan) -> Array[String] {
  self.hooks.map(h => h.name())
}

///|
pub fn HookPlan::length(self : HookPlan) -> Int {
  self.hooks.length()
}

///|
pub(all) struct BeforeResult {
  context : EvaluationContext
  error : SdkError?
}

///|
pub fn HookPlan::before(
  self : HookPlan,
  context : HookContext,
  hints : EvaluationContext,
) -> BeforeResult {
  let mut merged = context.evaluation_context.copy()
  for index, hook in self.hooks {
    let current = { ..context.with_context(merged), data: self.data[index] }
    match (hook.before)(current, hints.copy()) {
      Ok(None) => ()
      Ok(Some(additional)) => merged = merged.merge(additional)
      Err(error) => return { context: merged, error: Some(error) }
    }
  }
  { context: merged, error: None }
}

///|
pub fn HookPlan::after(
  self : HookPlan,
  context : HookContext,
  details : EvaluationDetails,
  hints : EvaluationContext,
) -> Result[Unit, SdkError] {
  let mut index = self.hooks.length() - 1
  while index >= 0 {
    match (self.hooks[index].after)({ ..context.copy(), data: self.data[index] }, details.copy(), hints.copy()) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    index -= 1
  }
  Ok(())
}

///|
/// Errors raised by error/finally observers are collected, not recursively
/// propagated into evaluation. One broken observer cannot suppress the others.
pub fn HookPlan::on_error(
  self : HookPlan,
  context : HookContext,
  error : SdkError,
  hints : EvaluationContext,
) -> Array[SdkError] {
  let diagnostics = []
  let mut index = self.hooks.length() - 1
  while index >= 0 {
    match (self.hooks[index].error)({ ..context.copy(), data: self.data[index] }, error, hints.copy()) {
      Ok(_) => ()
      Err(observer_error) => diagnostics.push(observer_error)
    }
    index -= 1
  }
  diagnostics
}

///|
pub fn HookPlan::run_finally(
  self : HookPlan,
  context : HookContext,
  details : EvaluationDetails,
  hints : EvaluationContext,
) -> Array[SdkError] {
  let diagnostics = []
  let mut index = self.hooks.length() - 1
  while index >= 0 {
    match (self.hooks[index].on_finally)({ ..context.copy(), data: self.data[index] }, details.copy(), hints.copy()) {
      Ok(_) => ()
      Err(observer_error) => diagnostics.push(observer_error)
    }
    index -= 1
  }
  diagnostics
}
