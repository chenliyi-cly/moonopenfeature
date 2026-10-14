///|
/// Scalar-only flag metadata, separate from structured evaluation context.
pub struct FlagMetadata {
  priv values : Map[String, Json]
}

///|
pub fn FlagMetadata::empty() -> FlagMetadata {
  { values: Map([]), }
}

///|
pub fn FlagMetadata::from_values(
  values : Map[String, Json],
) -> Result[FlagMetadata, SdkError] {
  let result = FlagMetadata::empty()
  for key, value in values {
    match result.set(key, value) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(result)
}

///|
fn FlagMetadata::set(
  self : FlagMetadata,
  key : String,
  value : Json,
) -> Result[Unit, SdkError] {
  match value {
    String(_) | True | False => {
      self.values[key] = value
      Ok(())
    }
    Number(number, ..) =>
      if number.is_nan() || number.is_inf() {
        Err(SdkError::new(ParseError, "metadata number must be finite"))
      } else {
        match validate_json(value) {
          Err(_) =>
            Err(
              SdkError::new(
                ParseError,
                "metadata number has an invalid JSON representation",
              ),
            )
          Ok(_) => {
            self.values[key] = value
            Ok(())
          }
        }
      }
    _ =>
      Err(
        SdkError::new(
          ParseError,
          "flag metadata must contain only scalar values",
        ),
      )
  }
}

///|
pub fn FlagMetadata::with_value(
  self : FlagMetadata,
  key : String,
  value : Json,
) -> Result[FlagMetadata, SdkError] {
  let result = self.copy()
  match result.set(key, value) {
    Ok(_) => Ok(result)
    Err(error) => Err(error)
  }
}

///|
pub fn FlagMetadata::get(self : FlagMetadata, key : String) -> Json? {
  self.values.get(key)
}

///|
pub fn FlagMetadata::values(self : FlagMetadata) -> Map[String, Json] {
  self.values.copy()
}

///|
pub fn FlagMetadata::copy(self : FlagMetadata) -> FlagMetadata {
  { values: self.values.copy(), }
}

///|
pub fn FlagMetadata::merge(
  self : FlagMetadata,
  later : FlagMetadata,
) -> FlagMetadata {
  let result = self.copy()
  for key, value in later.values {
    result.values[key] = value
  }
  result
}

///|
pub fn FlagMetadata::to_json(self : FlagMetadata) -> Json {
  Json::object(self.values.copy())
}
