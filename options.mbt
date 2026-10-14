///|
pub struct EvaluationOptions {
  priv context : EvaluationContext
  priv transaction_context : EvaluationContext
  priv hooks : Array[Hook]
  priv hints : EvaluationContext
}

///|
pub fn EvaluationOptions::new(
  context~ : EvaluationContext = EvaluationContext::empty(),
  transaction_context~ : EvaluationContext = EvaluationContext::empty(),
  hooks~ : Array[Hook] = [],
  hints~ : EvaluationContext = EvaluationContext::empty(),
) -> EvaluationOptions {
  {
    context: context.copy(),
    transaction_context: transaction_context.copy(),
    hooks: hooks.copy(),
    hints: hints.copy(),
  }
}

///|
pub fn EvaluationOptions::context(
  self : EvaluationOptions,
) -> EvaluationContext {
  self.context.copy()
}

///|
pub fn EvaluationOptions::transaction_context(
  self : EvaluationOptions,
) -> EvaluationContext {
  self.transaction_context.copy()
}

///|
pub fn EvaluationOptions::hooks(self : EvaluationOptions) -> Array[Hook] {
  self.hooks.copy()
}

///|
pub fn EvaluationOptions::hints(self : EvaluationOptions) -> EvaluationContext {
  self.hints.copy()
}

///|
pub fn EvaluationOptions::copy(self : EvaluationOptions) -> EvaluationOptions {
  EvaluationOptions::new(
    context=self.context,
    transaction_context=self.transaction_context,
    hooks=self.hooks,
    hints=self.hints,
  )
}
