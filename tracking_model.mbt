///|
/// A tracking payload. The nonempty key constraint is a local safety extension
/// to the specification. Public field construction bypasses constructor checks;
/// use new for validated events and copy at callback ownership boundaries.
pub(all) struct TrackingEvent {
  key : String
  value : Double?
  details : EvaluationContext
}

///|
pub fn TrackingEvent::new(
  key : String,
  value? : Double? = None,
  details? : EvaluationContext = EvaluationContext::empty(),
) -> Result[TrackingEvent, SdkError] {
  if key == "" {
    return Err(SdkError::new(General, "tracking event key must not be empty"))
  }
  match value {
    Some(number) =>
      if number.is_nan() || number.is_inf() {
        return Err(
          SdkError::new(General, "tracking event value must be finite"),
        )
      }
    None => ()
  }
  Ok({ key, value, details: details.copy(), })
}

///|
pub fn TrackingEvent::copy(self : TrackingEvent) -> TrackingEvent {
  { ..self, details: self.details.copy(), }
}

///|
/// Serialize a validated payload; absent value is omitted, not null. Context
/// JSON preserves its targeting key and snapshots nested detail containers.
pub fn TrackingEvent::to_json(self : TrackingEvent) -> Json {
  let fields : Map[String, Json] = {
    "key": Json::string(self.key),
    "details": self.details.to_json(),
  }
  match self.value {
    Some(value) => fields["value"] = Json::number(value)
    None => ()
  }
  Json::object(fields)
}
