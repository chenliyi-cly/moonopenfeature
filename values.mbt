///|
/// The five OpenFeature flag types. Integers remain distinct from floating point.
pub(all) enum FlagType {
  Boolean
  Integer
  Float
  String
  Structure
} derive(Eq)

///|
pub extend FlagType with Eq::{equal, not_equal}

///|
/// Structure flags accept JSON objects, arrays and null, not JSON scalars.
/// Raw enum construction does not validate or take ownership of mutable JSON.
/// Providers and callbacks must validate their result before publishing it and
/// use copy() when crossing an ownership boundary.
pub(all) enum FlagValue {
  Boolean(Bool)
  Integer(Int64)
  Float(Double)
  String(String)
  Structure(Json)
}

///|
pub fn FlagValue::flag_type(self : FlagValue) -> FlagType {
  match self {
    Boolean(_) => Boolean
    Integer(_) => Integer
    Float(_) => Float
    String(_) => String
    Structure(_) => Structure
  }
}

///|
/// Copy a validated flag, detaching every mutable JSON container.
/// Invalid JSON trees are replaced by null; call validate() to report errors.
pub fn FlagValue::copy(self : FlagValue) -> FlagValue {
  match self {
    Boolean(value) => Boolean(value)
    Integer(value) => Integer(value)
    Float(value) => Float(value)
    String(value) => String(value)
    Structure(value) => Structure(copy_json(value))
  }
}

///|
pub fn FlagValue::validate(self : FlagValue) -> Result[Unit, SdkError] {
  match self {
    Float(value) =>
      if value.is_nan() || value.is_inf() {
        Err(SdkError::new(TypeMismatch, "floating point flag must be finite"))
      } else {
        Ok(())
      }
    Structure(value) =>
      match value {
        Object(_) | Array(_) | Null => validate_json(value)
        _ =>
          Err(
            SdkError::new(
              TypeMismatch,
              "structure flag must be object, array or null",
            ),
          )
      }
    Boolean(_) | Integer(_) | String(_) => Ok(())
  }
}

///|
/// Accessors perform exact type checks, never coercion or numeric narrowing.
pub fn FlagValue::as_boolean(self : FlagValue) -> Bool? {
  match self {
    Boolean(value) => Some(value)
    _ => None
  }
}

///|
pub fn FlagValue::as_integer(self : FlagValue) -> Int64? {
  match self {
    Integer(value) => Some(value)
    _ => None
  }
}

///|
pub fn FlagValue::as_float(self : FlagValue) -> Double? {
  match self {
    Float(value) => Some(value)
    _ => None
  }
}

///|
pub fn FlagValue::as_string(self : FlagValue) -> String? {
  match self {
    String(value) => Some(value)
    _ => None
  }
}

///|
/// The returned JSON is detached, including nested objects and arrays.
pub fn FlagValue::as_structure(self : FlagValue) -> Json? {
  match self {
    Structure(value) => Some(copy_json(value))
    _ => None
  }
}

///|
/// Serialize a validated flag. Int64's original decimal representation avoids
/// loss of precision when JSON is stringified, despite Json's Double payload.
/// This is not a validation API: call validate() before serialization.
pub fn FlagValue::to_json(self : FlagValue) -> Json {
  match self {
    Boolean(value) => Json::boolean(value)
    Integer(value) => Json::number(value.to_double(), repr=value.to_string())
    Float(value) => Json::number(value)
    String(value) => Json::string(value)
    Structure(value) => copy_json(value)
  }
}
