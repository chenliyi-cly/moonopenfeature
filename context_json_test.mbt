///|
fn json_boundary_nested(depth : Int32) -> Json {
  let mut result = Json::null()
  for _ in 0..<depth {
    result = Json::array([result])
  }
  result
}

///|
test "JSON boundary depth zero through 64 and rejection at 65" {
  assert_true(@moonopenfeature.validate_json(Json::null()) is Ok(_))
  let allowed = json_boundary_nested(64)
  assert_true(@moonopenfeature.validate_json(allowed) is Ok(_))
  assert_true(@moonopenfeature.copy_json(allowed) == allowed)
  assert_true(
    @moonopenfeature.FlagValue::Structure(allowed).validate() is Ok(_),
  )
  let rejected = json_boundary_nested(65)
  let error = @moonopenfeature.validate_json(rejected).unwrap_err()
  assert_true(error.code == @moonopenfeature.ErrorCode::InvalidContext)
  assert_true(error.message.length() > 0)
  assert_true(@moonopenfeature.copy_json(rejected) == Json::null())
  assert_true(
    @moonopenfeature.FlagValue::Structure(rejected).validate() is Err(_),
  )
}

///|
test "JSON boundary context reserves one level for wire envelope" {
  let allowed = json_boundary_nested(63)
  let context = @moonopenfeature.EvaluationContext::from_attributes({
    "x": allowed,
  }).unwrap()
  assert_true(@moonopenfeature.validate_json(context.to_json()) is Ok(_))
  assert_true(
    @moonopenfeature.EvaluationContext::from_json(context.to_json()) is Ok(_),
  )
  assert_true(context.with_attribute("y", allowed) is Ok(_))
  let rejected = json_boundary_nested(64)
  assert_true(
    @moonopenfeature.EvaluationContext::from_attributes({ "x": rejected })
    is Err(_),
  )
  assert_true(context.with_attribute("y", rejected) is Err(_))
  assert_true(
    @moonopenfeature.EvaluationContext::from_json(
      Json::object({ "x": rejected }),
    )
    is Err(_),
  )
}

///|
test "JSON boundary rejects array object and mixed cycles" {
  let items : Array[Json] = []
  let fields : Map[String, Json] = Map([])
  let array = Json::array(items)
  let object = Json::object(fields)
  items.push(array)
  assert_true(@moonopenfeature.validate_json(array) is Err(_))
  assert_true(@moonopenfeature.copy_json(array) == Json::null())
  items.clear()
  fields.set("self", object)
  assert_true(@moonopenfeature.validate_json(object) is Err(_))
  assert_true(@moonopenfeature.copy_json(object) == Json::null())
  fields.clear()
  items.push(object)
  fields.set("back", array)
  assert_true(@moonopenfeature.validate_json(array) is Err(_))
  assert_true(@moonopenfeature.validate_json(object) is Err(_))
  items.clear()
  fields.clear()
}

///|
test "JSON boundary allows shared DAG and copy separates sibling containers" {
  let fields : Map[String, Json] = { "value": Json::string("original") }
  let shared = Json::object(fields)
  let source = Json::array([shared, shared])
  assert_true(@moonopenfeature.validate_json(source) is Ok(_))
  let copied = @moonopenfeature.copy_json(source)
  guard copied is Array(items) else { fail("expected array") }
  guard items[0] is Object(left) else { fail("expected left object") }
  guard items[1] is Object(right) else { fail("expected right object") }
  left.set("value", Json::string("changed"))
  assert_true(right.get("value") == Some(Json::string("original")))
  assert_true(fields.get("value") == Some(Json::string("original")))
  fields.clear()
  assert_true(right.get("value") == Some(Json::string("original")))
}

///|
test "JSON boundary copies scalars and rejects nonfinite with or without repr" {
  for
    json in [
      Json::null(),
      Json::boolean(true),
      Json::boolean(false),
      Json::string("x"),
      Json::number(-0.0),
    ] {
    assert_true(@moonopenfeature.validate_json(json) is Ok(_))
    assert_true(@moonopenfeature.copy_json(json) == json)
  }
  let zero = 0.0
  for number in [1.0 / zero, -1.0 / zero, zero / zero] {
    for json in [Json::number(number), Json::number(number, repr="0")] {
      assert_true(
        @moonopenfeature.validate_json(json)
        is Err({ code: InvalidContext, .. }),
      )
      assert_true(@moonopenfeature.copy_json(json) == Json::null())
    }
  }
}

///|
test "JSON boundary numeric repr grammar blocks raw serialization injection" {
  for
    repr in [
      "0", "-0", "123", "-123", "0.25", "-1.25", "1e9", "1E+9", "1e-9", "9223372036854775807",
    ] {
    let json = Json::number(1.0, repr~)
    assert_true(@moonopenfeature.validate_json(json) is Ok(_))
    guard @moonopenfeature.copy_json(json) is Number(_, repr=copied) else {
      fail("expected number")
    }
    assert_true(copied == Some(repr))
  }
  for
    repr in [
      "", "-", "+1", "01", "-01", ".1", "1.", "1e", "1e+", "1e-", "NaN", "Infinity",
      "1,null", " 1", "1 ", "１", "--1",
    ] {
    let json = Json::number(1.0, repr~)
    assert_true(@moonopenfeature.validate_json(json) is Err(_))
    assert_true(@moonopenfeature.copy_json(json) == Json::null())
  }
}

///|
test "context JSON roundtrip reserved targeting key and arbitrary attributes" {
  let source = Json::object({
    "targetingKey": Json::string("user-1"),
    "": Json::boolean(false),
    "number": Json::number(3.5),
    "nested": Json::array([
      Json::object({ "ok": Json::boolean(true) }),
      Json::null(),
    ]),
  })
  let context = @moonopenfeature.EvaluationContext::from_json(source).unwrap()
  assert_true(context.targeting_key() == Some("user-1"))
  assert_true(context.get("targetingKey") == None)
  assert_true(context.get("") == Some(Json::boolean(false)))
  assert_eq(context.attributes().length(), 3)
  assert_true(context.to_json() == source)
  let again = @moonopenfeature.EvaluationContext::from_json(context.to_json()).unwrap()
  assert_true(again.targeting_key() == context.targeting_key())
  assert_true(again.attributes() == context.attributes())
}

///|
test "context JSON empty absent empty string and invalid targeting keys" {
  let absent = @moonopenfeature.EvaluationContext::from_json(Json::object({})).unwrap()
  assert_true(absent.targeting_key() == None)
  assert_true(absent.to_json() == Json::object({}))
  let empty = @moonopenfeature.EvaluationContext::from_json(
    Json::object({ "targetingKey": Json::string("") }),
  ).unwrap()
  assert_true(empty.targeting_key() == Some(""))
  for
    value in [
      Json::null(),
      Json::number(1.0),
      Json::boolean(true),
      Json::array([]),
      Json::object({}),
    ] {
    assert_true(
      @moonopenfeature.EvaluationContext::from_json(
        Json::object({ "targetingKey": value }),
      )
      is Err({ code: InvalidContext, .. }),
    )
  }
  for
    value in [
      Json::null(),
      Json::boolean(false),
      Json::number(1.0),
      Json::array([]),
      Json::string("{}"),
    ] {
    assert_true(
      @moonopenfeature.EvaluationContext::from_json(value)
      is Err({ code: InvalidContext, .. }),
    )
  }
}

///|
test "context JSON source and output nested mutations do not leak" {
  let items = [Json::number(7.0)]
  let fields : Map[String, Json] = {
    "targetingKey": Json::string("original"),
    "items": Json::array(items),
  }
  let context = @moonopenfeature.EvaluationContext::from_json(
    Json::object(fields),
  ).unwrap()
  items.clear()
  fields.clear()
  let expected = Json::array([Json::number(7.0)])
  assert_true(context.targeting_key() == Some("original"))
  assert_true(context.get("items") == Some(expected))
  guard context.to_json() is Object(encoded) else {
    fail("expected wire object")
  }
  guard encoded.get("items") is Some(Array(exported)) else {
    fail("expected wire array")
  }
  exported.clear()
  encoded.set("targetingKey", Json::string("changed"))
  assert_true(context.targeting_key() == Some("original"))
  assert_true(context.get("items") == Some(expected))
}

///|
test "context JSON preserves numeric repr and documents reserved attribute collision" {
  let integer = @moonopenfeature.FlagValue::Integer(9223372036854775807L).to_json()
  let context = @moonopenfeature.EvaluationContext::from_attributes({
      "integer": integer,
      "targetingKey": Json::string("attribute"),
    })
    .unwrap()
    .with_targeting_key("identity")
  assert_true(context.get("targetingKey") == Some(Json::string("attribute")))
  guard context.to_json() is Object(fields) else { fail("expected object") }
  assert_true(fields.get("targetingKey") == Some(Json::string("identity")))
  guard fields.get("integer") is Some(Number(_, repr~)) else {
    fail("expected integer")
  }
  assert_true(repr == Some("9223372036854775807"))
  let decoded = @moonopenfeature.EvaluationContext::from_json(
    Json::object(fields),
  ).unwrap()
  assert_true(decoded.targeting_key() == Some("identity"))
  assert_true(decoded.get("targetingKey") == None)
}

///|
test "context JSON rejects invalid nested numbers and cycles" {
  let zero = 0.0
  assert_true(
    @moonopenfeature.EvaluationContext::from_json(
      Json::object({ "bad": Json::array([Json::number(zero / zero)]) }),
    )
    is Err({ code: InvalidContext, .. }),
  )
  let fields : Map[String, Json] = Map([])
  let cyclic = Json::object(fields)
  fields.set("self", cyclic)
  assert_true(
    @moonopenfeature.EvaluationContext::from_json(cyclic)
    is Err({ code: InvalidContext, .. }),
  )
  fields.clear()
}
