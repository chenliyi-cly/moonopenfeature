///|
/// Immutable-by-interface evaluation context. Constructors and accessors copy
/// JSON recursively; neither a caller's map nor a returned map aliases storage.
pub struct EvaluationContext {
  priv targeting_key : String?
  priv attributes : Map[String, Json]
}

///|
pub fn EvaluationContext::empty() -> EvaluationContext {
  { targeting_key: None, attributes: Map([]), }
}

///|
/// Keys, including the empty string, are allowed. Validate the whole envelope
/// so to_json() also satisfies the maximum JSON depth of 64.
pub fn EvaluationContext::from_attributes(
  attributes : Map[String, Json],
) -> Result[EvaluationContext, SdkError] {
  match validate_json(Json::object(attributes)) {
    Err(error) => Err(error)
    Ok(_) =>
      Ok({
        targeting_key: None,
        attributes: copy_context_attributes(attributes),
      })
  }
}

///|
/// A replacement, not an in-place mutation. Empty targeting keys are legal.
pub fn EvaluationContext::with_targeting_key(
  self : EvaluationContext,
  targeting_key : String,
) -> EvaluationContext {
  {
    targeting_key: Some(targeting_key),
    attributes: copy_context_attributes(self.attributes),
  }
}

///|
pub fn EvaluationContext::without_targeting_key(
  self : EvaluationContext,
) -> EvaluationContext {
  { targeting_key: None, attributes: copy_context_attributes(self.attributes), }
}

///|
/// Validate before copying or modifying anything; failure leaves self intact.
pub fn EvaluationContext::with_attribute(
  self : EvaluationContext,
  key : String,
  value : Json,
) -> Result[EvaluationContext, SdkError] {
  match validate_json(Json::object(Map([(key, value)]))) {
    Err(error) => Err(error)
    Ok(_) => {
      let attributes = copy_context_attributes(self.attributes)
      attributes.set(key, copy_json(value))
      Ok({ targeting_key: self.targeting_key, attributes, })
    }
  }
}

///|
pub fn EvaluationContext::without_attribute(
  self : EvaluationContext,
  key : String,
) -> EvaluationContext {
  let attributes = copy_context_attributes(self.attributes)
  attributes.remove(key)
  { targeting_key: self.targeting_key, attributes, }
}

///|
pub fn EvaluationContext::get(self : EvaluationContext, key : String) -> Json? {
  match self.attributes.get(key) {
    Some(value) => Some(copy_json(value))
    None => None
  }
}

///|
pub fn EvaluationContext::targeting_key(self : EvaluationContext) -> String? {
  self.targeting_key
}

///|
pub fn EvaluationContext::attributes(
  self : EvaluationContext,
) -> Map[String, Json] {
  copy_context_attributes(self.attributes)
}

///|
pub fn EvaluationContext::copy(self : EvaluationContext) -> EvaluationContext {
  {
    targeting_key: self.targeting_key,
    attributes: copy_context_attributes(self.attributes),
  }
}

///|
/// Later attributes replace earlier values atomically, without recursive JSON
/// object merging. A present later targeting key wins, including an empty key;
/// an absent later targeting key preserves the earlier key.
pub fn EvaluationContext::merge(
  self : EvaluationContext,
  later : EvaluationContext,
) -> EvaluationContext {
  let attributes = copy_context_attributes(self.attributes)
  for key, value in later.attributes {
    attributes.set(key, copy_json(value))
  }
  let targeting_key = match later.targeting_key {
    Some(_) => later.targeting_key
    None => self.targeting_key
  }
  { targeting_key, attributes, }
}

///|
fn copy_context_attributes(source : Map[String, Json]) -> Map[String, Json] {
  let result = Map([])
  for key, value in source {
    result.set(key, copy_json(value))
  }
  result
}
