///|
test "context empty and unrestricted keys" {
  let empty = @moonopenfeature.EvaluationContext::empty()
  assert_true(empty.targeting_key() == None)
  assert_eq(empty.attributes().length(), 0)
  assert_true(empty.get("missing") == None)
  let context = empty.with_attribute("", Json::string("empty key")).unwrap()
    .with_attribute("中文", Json::null()).unwrap()
    .with_targeting_key("")
  assert_true(context.get("") == Some(Json::string("empty key")))
  assert_true(context.get("中文") == Some(Json::null()))
  assert_true(context.targeting_key() == Some(""))
  assert_true(empty.get("") == None)
  assert_true(empty.targeting_key() == None)
}

///|
test "context source map array and nested object mutation isolation" {
  let fields : Map[String, Json] = { "tier": Json::string("gold") }
  let items = [Json::object(fields)]
  let source : Map[String, Json] = { "profile": Json::array(items) }
  let context = @moonopenfeature.EvaluationContext::from_attributes(source).unwrap()
  let expected = Json::array([Json::object({ "tier": Json::string("gold") })])
  source.set("extra", Json::boolean(true))
  source.remove("profile")
  fields.set("tier", Json::string("silver"))
  items.clear()
  assert_true(context.get("profile") == Some(expected))
  assert_true(context.get("extra") == None)
  guard context.get("profile") is Some(Array(returned)) else { fail("expected array") }
  guard returned[0] is Object(returned_fields) else { fail("expected object") }
  returned_fields.clear()
  returned.push(Json::null())
  assert_true(context.get("profile") == Some(expected))
  let attrs = context.attributes()
  guard attrs.get("profile") is Some(Array(exported)) else { fail("expected exported array") }
  exported.clear()
  attrs.set("extra", Json::null())
  assert_true(context.get("profile") == Some(expected))
  assert_eq(context.attributes().length(), 1)
}

///|
test "context with attribute copies incoming values and replaces atomically" {
  let original = @moonopenfeature.EvaluationContext::empty()
    .with_attribute("x", Json::number(1.0)).unwrap().with_targeting_key("user")
  let fields : Map[String, Json] = { "nested": Json::boolean(true) }
  let changed = original.with_attribute("x", Json::object(fields)).unwrap()
  fields.clear()
  assert_true(original.get("x") == Some(Json::number(1.0)))
  assert_true(changed.get("x") == Some(Json::object({ "nested": Json::boolean(true) })))
  assert_true(changed.targeting_key() == Some("user"))
  let removed = changed.without_attribute("x")
  assert_true(removed.get("x") == None)
  assert_true(removed.targeting_key() == Some("user"))
  assert_true(changed.get("x") is Some(_))
  assert_true(changed.without_attribute("absent").get("x") == changed.get("x"))
}

///|
test "context copy and targeting key changes preserve independent values" {
  let original = @moonopenfeature.EvaluationContext::from_attributes({
    "nested": Json::array([Json::string("v")]),
  }).unwrap().with_targeting_key("before")
  let copied = original.copy()
  let changed = copied.with_targeting_key("after")
  let cleared = changed.without_targeting_key()
  assert_true(original.targeting_key() == Some("before"))
  assert_true(copied.targeting_key() == Some("before"))
  assert_true(changed.targeting_key() == Some("after"))
  assert_true(cleared.targeting_key() == None)
  assert_true(cleared.get("nested") == original.get("nested"))
  let attributes = copied.attributes()
  guard attributes.get("nested") is Some(Array(items)) else { fail("expected array") }
  items.clear()
  attributes.clear()
  assert_true(original.get("nested") == Some(Json::array([Json::string("v")])))
  assert_true(copied.get("nested") == original.get("nested"))
}

///|
test "context merge later wins without recursive object merging" {
  let earlier = @moonopenfeature.EvaluationContext::from_attributes({
    "keep": Json::number(1.0),
    "replace": Json::object({ "old": Json::boolean(true) }),
    "null": Json::string("old"),
  }).unwrap().with_targeting_key("earlier")
  let later = @moonopenfeature.EvaluationContext::from_attributes({
    "replace": Json::object({ "new": Json::boolean(false) }),
    "null": Json::null(),
    "add": Json::array([]),
  }).unwrap().with_targeting_key("later")
  let merged = earlier.merge(later)
  assert_true(merged.targeting_key() == Some("later"))
  assert_true(merged.get("keep") == Some(Json::number(1.0)))
  assert_true(merged.get("replace") == Some(Json::object({ "new": Json::boolean(false) })))
  assert_true(merged.get("null") == Some(Json::null()))
  assert_true(merged.get("add") == Some(Json::array([])))
  assert_eq(merged.attributes().length(), 4)
  assert_true(earlier.get("replace") == Some(Json::object({ "old": Json::boolean(true) })))
  assert_true(later.get("keep") == None)
  guard merged.get("replace") is Some(Object(fields)) else { fail("expected object") }
  fields.clear()
  assert_true(merged.get("replace") == later.get("replace"))
}

///|
test "context merge absent targeting key inherits and empty key overrides" {
  let first = @moonopenfeature.EvaluationContext::empty().with_targeting_key("first")
  let absent = @moonopenfeature.EvaluationContext::empty()
  assert_true(first.merge(absent).targeting_key() == Some("first"))
  assert_true(absent.merge(first).targeting_key() == Some("first"))
  assert_true(first.merge(absent.with_targeting_key("")).targeting_key() == Some(""))
  assert_true(absent.merge(absent).targeting_key() == None)
  assert_true(first.merge(first).targeting_key() == Some("first"))
}

///|
test "context rejects cyclic and nonfinite attributes without changing original" {
  let original = @moonopenfeature.EvaluationContext::empty().with_targeting_key("key")
  let fields : Map[String, Json] = Map([])
  let cyclic = Json::object(fields)
  fields.set("self", cyclic)
  assert_true(original.with_attribute("bad", cyclic) is Err({ code: InvalidContext, .. }))
  assert_true(@moonopenfeature.EvaluationContext::from_attributes(fields)
    is Err({ code: InvalidContext, .. }))
  fields.clear()
  let zero = 0.0
  for number in [1.0 / zero, -1.0 / zero, zero / zero] {
    let value = Json::object({ "nested": Json::array([Json::number(number)]) })
    assert_true(original.with_attribute("bad", value) is Err({ code: InvalidContext, .. }))
    assert_true(@moonopenfeature.EvaluationContext::from_attributes({ "bad": value })
      is Err({ code: InvalidContext, .. }))
  }
  assert_true(original.get("bad") == None)
  assert_true(original.targeting_key() == Some("key"))
}
