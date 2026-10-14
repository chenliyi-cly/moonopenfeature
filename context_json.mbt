///|
/// Validate an in-memory JSON tree, not JSON text. The root has depth zero;
/// values reached by at most 64 object/array edges are accepted. Cycles are
/// checked by container identity on the active path, so shared acyclic subtrees
/// remain legal. Non-finite numbers and malformed numeric repr are rejected.
pub fn validate_json(value : Json) -> Result[Unit, SdkError] {
  validate_json_at(value, 0, [])
}

///|
fn validate_json_at(
  value : Json,
  depth : Int32,
  ancestors : Array[Json],
) -> Result[Unit, SdkError] {
  if depth > 64 {
    return Err(SdkError::new(InvalidContext, "JSON depth exceeds 64"))
  }
  match value {
    Number(number, repr~) => {
      if number.is_nan() || number.is_inf() {
        return Err(SdkError::new(InvalidContext, "JSON number must be finite"))
      }
      if repr is Some(text) && !valid_number_repr(text) {
        return Err(
          SdkError::new(InvalidContext, "invalid JSON number representation"),
        )
      }
      Ok(())
    }
    Array(items) => {
      for ancestor in ancestors {
        if ancestor is Array(previous) && physical_equal(items, previous) {
          return Err(SdkError::new(InvalidContext, "cyclic JSON array"))
        }
      }
      ancestors.push(value)
      for item in items {
        match validate_json_at(item, depth + 1, ancestors) {
          Err(error) => {
            ignore(ancestors.pop())
            return Err(error)
          }
          Ok(_) => ()
        }
      }
      ignore(ancestors.pop())
      Ok(())
    }
    Object(fields) => {
      for ancestor in ancestors {
        if ancestor is Object(previous) && physical_equal(fields, previous) {
          return Err(SdkError::new(InvalidContext, "cyclic JSON object"))
        }
      }
      ancestors.push(value)
      for _, item in fields {
        match validate_json_at(item, depth + 1, ancestors) {
          Err(error) => {
            ignore(ancestors.pop())
            return Err(error)
          }
          Ok(_) => ()
        }
      }
      ignore(ancestors.pop())
      Ok(())
    }
    Null | True | False | String(_) => Ok(())
  }
}

///|
/// Json permits a raw numeric repr used verbatim by stringification. Check its
/// grammar without converting to Double: conversion would lose Int64 precision.
fn valid_number_repr(text : String) -> Bool {
  let chars = text.to_array()
  let length = chars.length()
  let mut index = 0
  if index < length && chars[index] == '-' {
    index += 1
  }
  if index >= length {
    return false
  }
  if chars[index] == '0' {
    index += 1
  } else if chars[index] >= '1' && chars[index] <= '9' {
    while index < length && chars[index] >= '0' && chars[index] <= '9' {
      index += 1
    }
  } else {
    return false
  }
  if index < length && chars[index] == '.' {
    index += 1
    let start = index
    while index < length && chars[index] >= '0' && chars[index] <= '9' {
      index += 1
    }
    if index == start {
      return false
    }
  }
  if index < length && (chars[index] == 'e' || chars[index] == 'E') {
    index += 1
    if index < length && (chars[index] == '+' || chars[index] == '-') {
      index += 1
    }
    let start = index
    while index < length && chars[index] >= '0' && chars[index] <= '9' {
      index += 1
    }
    if index == start {
      return false
    }
  }
  index == length
}

///|
/// Deep-copy a validated JSON tree, preserving numeric repr and all keys.
/// Validate first when errors must be reported. Invalid inputs fail closed to
/// null rather than recursing forever or returning an aliased mutable value.
pub fn copy_json(value : Json) -> Json {
  match validate_json(value) {
    Ok(_) => copy_validated_json(value, 0)
    Err(_) => Json::null()
  }
}

///|
fn copy_validated_json(value : Json, depth : Int32) -> Json {
  // Defensive bound: even this private copier terminates on unvalidated input.
  if depth > 64 {
    return Json::null()
  }
  match value {
    Null => Json::null()
    True => Json::boolean(true)
    False => Json::boolean(false)
    String(text) => Json::string(text)
    Number(number, repr~) =>
      match repr {
        Some(text) => Json::number(number, repr=text)
        None => Json::number(number)
      }
    Array(items) => {
      let copied = []
      for item in items {
        copied.push(copy_validated_json(item, depth + 1))
      }
      Json::array(copied)
    }
    Object(fields) => {
      let copied = Map([])
      for key, item in fields {
        copied.set(key, copy_validated_json(item, depth + 1))
      }
      Json::object(copied)
    }
  }
}

///|
/// The wire format is a flat object; targetingKey is a reserved wire field.
/// Attribute keys are unrestricted in memory. If an attribute has that spelling
/// and a targeting key is present, the targeting key wins in the wire object.
/// from_json always interprets that field as the targeting key, not an attribute.
pub fn EvaluationContext::to_json(self : EvaluationContext) -> Json {
  let fields = self.attributes()
  match self.targeting_key() {
    Some(key) => fields.set("targetingKey", Json::string(key))
    None => ()
  }
  Json::object(fields)
}

///|
/// Read an already parsed JSON object. The reserved targetingKey, when present,
/// must be a string (null is not equivalent to absence). Other fields are copied
/// as attributes. No string parsing, coercion or recursive object merging occurs.
pub fn EvaluationContext::from_json(
  value : Json,
) -> Result[EvaluationContext, SdkError] {
  guard value is Object(fields) else {
    return Err(
      SdkError::new(InvalidContext, "evaluation context must be a JSON object"),
    )
  }
  match validate_json(value) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let mut targeting_key : String? = None
  let attributes = Map([])
  for key, item in fields {
    if key == "targetingKey" {
      guard item is String(text) else {
        return Err(
          SdkError::new(InvalidContext, "targetingKey must be a string"),
        )
      }
      targeting_key = Some(text)
    } else {
      attributes.set(key, copy_json(item))
    }
  }
  // Both maps and targeting key are locally owned; avoid another envelope copy.
  Ok({ targeting_key, attributes, })
}
