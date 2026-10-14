///|
test "values exact type and typed accessors" {
  let boolean = @moonopenfeature.FlagValue::Boolean(true)
  let integer = @moonopenfeature.FlagValue::Integer(9007199254740993L)
  let float = @moonopenfeature.FlagValue::Float(2.5)
  let string = @moonopenfeature.FlagValue::String("flag")
  let structure = @moonopenfeature.FlagValue::Structure(Json::null())
  assert_true(boolean.flag_type() == @moonopenfeature.FlagType::Boolean)
  assert_true(integer.flag_type() == @moonopenfeature.FlagType::Integer)
  assert_true(float.flag_type() == @moonopenfeature.FlagType::Float)
  assert_true(string.flag_type() == @moonopenfeature.FlagType::String)
  assert_true(structure.flag_type() == @moonopenfeature.FlagType::Structure)
  assert_true(
    @moonopenfeature.FlagType::Boolean != @moonopenfeature.FlagType::Integer,
  )
  assert_true(boolean.as_boolean() == Some(true))
  assert_true(integer.as_integer() == Some(9007199254740993L))
  assert_true(float.as_float() == Some(2.5))
  assert_true(string.as_string() == Some("flag"))
  assert_true(structure.as_structure() == Some(Json::null()))
  for value in [boolean, integer, float, string, structure] {
    assert_true(value.validate() is Ok(_))
    if value.flag_type() != @moonopenfeature.FlagType::Boolean {
      assert_true(value.as_boolean() == None)
    }
    if value.flag_type() != @moonopenfeature.FlagType::Integer {
      assert_true(value.as_integer() == None)
    }
    if value.flag_type() != @moonopenfeature.FlagType::Float {
      assert_true(value.as_float() == None)
    }
    if value.flag_type() != @moonopenfeature.FlagType::String {
      assert_true(value.as_string() == None)
    }
    if value.flag_type() != @moonopenfeature.FlagType::Structure {
      assert_true(value.as_structure() == None)
    }
  }
}

///|
test "values scalar copies and serialization" {
  let boolean = @moonopenfeature.FlagValue::Boolean(false)
  let integer = @moonopenfeature.FlagValue::Integer(-7L)
  let float = @moonopenfeature.FlagValue::Float(-0.25)
  let string = @moonopenfeature.FlagValue::String("\"quoted\"\n中文")
  assert_true(boolean.copy().as_boolean() == Some(false))
  assert_true(integer.copy().as_integer() == Some(-7L))
  assert_true(float.copy().as_float() == Some(-0.25))
  assert_true(string.copy().as_string() == Some("\"quoted\"\n中文"))
  assert_true(boolean.to_json() == Json::boolean(false))
  assert_true(float.to_json() == Json::number(-0.25))
  assert_true(string.to_json() == Json::string("\"quoted\"\n中文"))
}

///|
test "values int64 representation survives rounding in JSON payload" {
  for
    integer in [
      0L, -1L, 9007199254740993L, 9223372036854775807L, -9223372036854775808L,
    ] {
    let value = @moonopenfeature.FlagValue::Integer(integer)
    assert_true(value.as_integer() == Some(integer))
    let encoded = value.to_json()
    guard encoded is Number(number, repr~) else { fail("expected number") }
    assert_true(number == integer.to_double())
    assert_true(repr == Some(integer.to_string()))
    assert_true(@moonopenfeature.validate_json(encoded) is Ok(_))
    guard @moonopenfeature.copy_json(encoded) is Number(_, repr=copied_repr) else {
      fail("expected copied number")
    }
    assert_true(copied_repr == repr)
  }
}

///|
test "values structures accept object array null but not scalars" {
  for json in [Json::object({}), Json::array([]), Json::null()] {
    assert_true(@moonopenfeature.FlagValue::Structure(json).validate() is Ok(_))
  }
  for
    json in [
      Json::boolean(true),
      Json::boolean(false),
      Json::number(1.0),
      Json::string("x"),
    ] {
    let error = @moonopenfeature.FlagValue::Structure(json)
      .validate()
      .unwrap_err()
    assert_true(error.code == @moonopenfeature.ErrorCode::TypeMismatch)
    assert_true(error.message.length() > 0)
  }
}

///|
test "values float and nested structure reject nonfinite numbers" {
  let zero = 0.0
  for number in [1.0 / zero, -1.0 / zero, zero / zero] {
    assert_true(
      @moonopenfeature.FlagValue::Float(number).validate()
      is Err({ code: TypeMismatch, .. }),
    )
    assert_true(
      @moonopenfeature.FlagValue::Structure(Json::array([Json::number(number)])).validate()
      is Err({ code: InvalidContext, .. }),
    )
  }
}

///|
test "values structure copy accessor and serialization detach containers" {
  let nested : Map[String, Json] = { "name": Json::string("original") }
  let items = [Json::object(nested)]
  let flag = @moonopenfeature.FlagValue::Structure(Json::array(items))
  let copied = flag.copy()
  nested.set("name", Json::string("source changed"))
  items.push(Json::null())
  let expected = Json::array([
    Json::object({ "name": Json::string("original") }),
  ])
  assert_true(copied.as_structure() == Some(expected))
  guard copied.as_structure() is Some(Array(result)) else {
    fail("expected array")
  }
  guard result[0] is Object(fields) else { fail("expected object") }
  fields.set("name", Json::string("getter changed"))
  result.push(Json::null())
  assert_true(copied.as_structure() == Some(expected))
  guard copied.to_json() is Array(encoded) else { fail("expected array") }
  encoded.clear()
  assert_true(copied.to_json() == expected)
}

///|
test "values cyclic structure validation and copying terminate" {
  let items : Array[Json] = []
  let cyclic = Json::array(items)
  items.push(cyclic)
  let value = @moonopenfeature.FlagValue::Structure(cyclic)
  assert_true(value.validate() is Err({ code: InvalidContext, .. }))
  assert_true(value.copy().as_structure() == Some(Json::null()))
  assert_true(value.to_json() == Json::null())
  items.clear()
}
