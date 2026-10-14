///|
test "tracking constructor defaults optional finite values and nonempty key extension" {
  let event = @moonopenfeature.TrackingEvent::new("click").unwrap()
  assert_eq(event.key, "click")
  assert_true(event.value == None)
  assert_eq(event.details.attributes().length(), 0)
  assert_true(event.details.targeting_key() == None)
  assert_true(
    @moonopenfeature.TrackingEvent::new("") is Err({ code: General, .. }),
  )
  assert_true(@moonopenfeature.TrackingEvent::new(" ") is Ok(_))
  for value in [0.0, -1.0, 42.5, 1.0e300, -1.0e300] {
    let event = @moonopenfeature.TrackingEvent::new(
      "measure",
      value=Some(value),
    ).unwrap()
    assert_true(event.value == Some(value))
  }
  for value in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(
      @moonopenfeature.TrackingEvent::new("invalid", value=Some(value))
      is Err({ code: General, .. }),
    )
  }
}

///|
test "tracking copies details and serialization keeps targeting key and omits absent value" {
  let input = [Json::string("original")]
  let details = @moonopenfeature.EvaluationContext::from_attributes({
      "items": Json::array(input),
    })
    .unwrap()
    .with_targeting_key("user")
  let event = @moonopenfeature.TrackingEvent::new("click", details~).unwrap()
  input.clear()
  let copied = event.copy()
  assert_true(copied.details.targeting_key() == Some("user"))
  assert_true(
    copied.details.get("items") == Some(Json::array([Json::string("original")])),
  )
  let expected = Json::object({
    "key": Json::string("click"),
    "details": Json::object({
      "targetingKey": Json::string("user"),
      "items": Json::array([Json::string("original")]),
    }),
  })
  assert_true(event.to_json() == expected)
  let wire = copied.to_json()
  guard wire is Object(fields) else {
    fail("tracking must serialize as an object")
  }
  assert_true(fields.get("value") == None)
  guard fields.get("details") is Some(Object(attributes)) else {
    fail("details missing")
  }
  guard attributes.get("items") is Some(Array(items)) else {
    fail("items missing")
  }
  items.clear()
  attributes.clear()
  fields.clear()
  assert_true(copied.to_json() == expected)
  assert_true(event.to_json() == expected)
}

///|
test "tracking numeric value and empty details have exact wire shape" {
  let event = @moonopenfeature.TrackingEvent::new("purchase", value=Some(-2.5)).unwrap()
  assert_true(
    event.to_json() ==
    Json::object({
      "key": Json::string("purchase"),
      "value": Json::number(-2.5),
      "details": Json::object(Map([])),
    }),
  )
}

///|
test "tracking public fields permit event construction and copy is independent" {
  let details = @moonopenfeature.EvaluationContext::empty().with_targeting_key(
    "subject",
  )
  let event : @moonopenfeature.TrackingEvent = {
    key: "custom",
    value: Some(0.0),
    details,
  }
  let copied = event.copy()
  assert_eq(copied.key, "custom")
  assert_true(copied.value == Some(0.0))
  assert_true(copied.details.targeting_key() == Some("subject"))
  guard copied.to_json() is Object(fields) else { fail("missing object") }
  fields["key"] = Json::string("changed")
  assert_eq(event.key, "custom")
  assert_eq(copied.key, "custom")
}
