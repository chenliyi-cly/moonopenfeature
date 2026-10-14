///|
/// Providers return this transport-independent resolution; the client validates
/// its value and substitutes the caller default on every error path.
pub(all) struct Resolution {
  value : FlagValue
  reason : String
  variant : String?
  error : SdkError?
  metadata : FlagMetadata
}

///|
pub fn Resolution::success(
  value : FlagValue,
  reason~ : String = "UNKNOWN",
  variant~ : String? = None,
  metadata~ : FlagMetadata = FlagMetadata::empty(),
) -> Resolution {
  { value, reason, variant, error: None, metadata: metadata.copy(), }
}

///|
pub fn Resolution::failure(default : FlagValue, error : SdkError) -> Resolution {
  {
    value: default,
    reason: "ERROR",
    variant: None,
    error: Some(error),
    metadata: FlagMetadata::empty(),
  }
}

///|
pub fn Resolution::checked(
  self : Resolution,
  expected : FlagType,
  default : FlagValue,
) -> Resolution {
  if self.error is Some(error) {
    return {
      ..Resolution::failure(default.copy(), error),
      metadata: self.metadata.copy(),
    }
  }
  if self.value.flag_type() != expected {
    return Resolution::failure(
      default.copy(),
      SdkError::new(TypeMismatch, "provider returned a different flag type"),
    )
  }
  match self.value.validate() {
    Err(error) => Resolution::failure(default.copy(), error)
    Ok(_) =>
      { ..self, value: self.value.copy(), metadata: self.metadata.copy(), }
  }
}

///|
pub(all) struct EvaluationDetails {
  flag_key : String
  value : FlagValue
  reason : String
  variant : String?
  error : SdkError?
  metadata : FlagMetadata
}

///|
pub fn EvaluationDetails::from_resolution(
  flag_key : String,
  resolution : Resolution,
) -> EvaluationDetails {
  {
    flag_key,
    value: resolution.value,
    reason: resolution.reason,
    variant: resolution.variant,
    error: resolution.error,
    metadata: resolution.metadata.copy(),
  }
}

///|
pub fn EvaluationDetails::copy(self : EvaluationDetails) -> EvaluationDetails {
  { ..self, value: self.value.copy(), metadata: self.metadata.copy(), }
}

///|
pub fn EvaluationDetails::is_error(self : EvaluationDetails) -> Bool {
  self.error is Some(_)
}

///|
pub fn EvaluationDetails::to_json(self : EvaluationDetails) -> Json {
  let result : Map[String, Json] = {
    "flagKey": Json::string(self.flag_key),
    "value": self.value.to_json(),
    "reason": Json::string(self.reason),
    "flagMetadata": self.metadata.to_json(),
  }
  match self.variant {
    Some(variant) => result["variant"] = Json::string(variant)
    None => ()
  }
  match self.error {
    Some(error) => {
      result["errorCode"] = Json::string(error.code.name())
      result["errorMessage"] = Json::string(error.message)
    }
    None => ()
  }
  Json::object(result)
}

///|
/// Typed results retain the shared diagnostic model without casting numeric types.
pub(all) struct Evaluation[T] {
  value : T
  details : EvaluationDetails
}

///|
pub fn[T] Evaluation::is_error(self : Evaluation[T]) -> Bool {
  self.details.is_error()
}
