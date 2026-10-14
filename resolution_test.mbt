///|
test "checked resolution keeps exact flag types and rejects every cross type pair" {
  let values : Array[@moonopenfeature.FlagValue] = [
    Boolean(true),
    Integer(9007199254740993L),
    Float(2.5),
    String("enabled"),
    Structure(Json::object({ "enabled": Json::boolean(true) })),
  ]
  let metadata = @moonopenfeature.FlagMetadata::from_values({
    "source": Json::string("provider"),
    "attempt": Json::number(2.0),
  }).unwrap()
  for returned in values {
    for default in values {
      let raw = @moonopenfeature.Resolution::success(
        returned,
        reason="VENDOR_REASON",
        variant=Some("blue"),
        metadata~,
      )
      let result = raw.checked(default.flag_type(), default)
      if returned.flag_type() == default.flag_type() {
        assert_true(result.error == None)
        assert_true(result.value.to_json() == returned.to_json())
        assert_eq(result.reason, "VENDOR_REASON")
        assert_true(result.variant == Some("blue"))
        assert_true(result.metadata.to_json() == metadata.to_json())
      } else {
        assert_true(result.error is Some({ code: TypeMismatch, .. }))
        assert_true(result.value.to_json() == default.to_json())
        assert_eq(result.reason, "ERROR")
        assert_true(result.variant == None)
        assert_eq(result.metadata.values().length(), 0)
      }
      assert_true(raw.error == None)
      assert_eq(raw.reason, "VENDOR_REASON")
      assert_true(raw.variant == Some("blue"))
    }
  }
  let plain = @moonopenfeature.Resolution::success(Boolean(false))
  assert_eq(plain.reason, "UNKNOWN")
  assert_true(plain.variant == None)
  assert_true(plain.error == None)
  assert_eq(plain.metadata.values().length(), 0)
}

///|
test "checked resolution validates nonfinite flags invalid structures and nested JSON" {
  for number in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    let result = @moonopenfeature.Resolution::success(Float(number)).checked(
      Float,
      Float(3.0),
    )
    assert_true(result.error is Some({ code: TypeMismatch, .. }))
    assert_true(result.value.as_float() == Some(3.0))
    assert_eq(result.reason, "ERROR")
    assert_true(result.variant == None)
  }
  for scalar in [Json::string("scalar"), Json::number(1.0), Json::boolean(true)] {
    let result = @moonopenfeature.Resolution::success(Structure(scalar)).checked(
      Structure,
      Structure(Json::null()),
    )
    assert_true(result.error is Some({ code: TypeMismatch, .. }))
    assert_true(result.value.as_structure() == Some(Json::null()))
  }
  let invalid = Json::object({
    "nested": Json::array([Json::number(1.0 / 0.0)]),
  })
  let result = @moonopenfeature.Resolution::success(Structure(invalid)).checked(
    Structure,
    Structure(Json::array([])),
  )
  assert_true(result.error is Some({ code: InvalidContext, .. }))
  assert_true(result.value.as_structure() == Some(Json::array([])))
  let valid = @moonopenfeature.Resolution::success(Structure(Json::null())).checked(
    Structure,
    Structure(Json::array([])),
  )
  assert_true(valid.error == None)
  assert_true(valid.value.as_structure() == Some(Json::null()))
}

///|
test "provider error takes precedence preserves metadata and snapshots caller default" {
  let error = @moonopenfeature.SdkError::new(FlagNotFound, "missing flag")
  let metadata = @moonopenfeature.FlagMetadata::from_values({
    "source": Json::string("remote"),
  }).unwrap()
  let raw : @moonopenfeature.Resolution = {
    value: Float(0.0 / 0.0),
    reason: "SHOULD_NOT_SURVIVE",
    variant: Some("wrong"),
    error: Some(error),
    metadata,
  }
  let items = [Json::string("fallback")]
  let result = raw.checked(Structure, Structure(Json::array(items)))
  items.clear()
  assert_true(result.error == Some(error))
  assert_eq(result.reason, "ERROR")
  assert_true(result.variant == None)
  assert_true(
    result.value.as_structure() == Some(Json::array([Json::string("fallback")])),
  )
  assert_true(result.metadata.get("source") == Some(Json::string("remote")))
  result.metadata.values().clear()
  assert_true(result.metadata.get("source") == Some(Json::string("remote")))
  assert_true(raw.metadata.get("source") == Some(Json::string("remote")))
  let failure = @moonopenfeature.Resolution::failure(Boolean(false), error)
  assert_true(failure.value.as_boolean() == Some(false))
  assert_true(failure.error == Some(error))
  assert_eq(failure.reason, "ERROR")
  assert_true(failure.variant == None)
  assert_eq(failure.metadata.values().length(), 0)
}

///|
test "details conversion copy and JSON detach value metadata and optional diagnostics" {
  let fields : Map[String, Json] = {
    "nested": Json::array([Json::string("original")]),
  }
  let metadata = @moonopenfeature.FlagMetadata::from_values({
    "source": Json::string("cache"),
  }).unwrap()
  let resolution = @moonopenfeature.Resolution::success(
    Structure(Json::object(fields)),
    reason="TARGETING_MATCH",
    variant=Some("green"),
    metadata~,
  ).checked(Structure, Structure(Json::null()))
  fields.clear()
  let details = @moonopenfeature.EvaluationDetails::from_resolution(
    "feature", resolution,
  )
  let copied = details.copy()
  assert_eq(copied.flag_key, "feature")
  assert_true(!details.is_error())
  let success : @moonopenfeature.Evaluation[Bool] = { value: true, details, }
  assert_true(!success.is_error())
  let expected = Json::object({
    "flagKey": Json::string("feature"),
    "value": Json::object({ "nested": Json::array([Json::string("original")]) }),
    "reason": Json::string("TARGETING_MATCH"),
    "variant": Json::string("green"),
    "flagMetadata": Json::object({ "source": Json::string("cache") }),
  })
  assert_true(copied.to_json() == expected)
  guard details.value is Structure(Object(original_fields)) else {
    fail("expected structure")
  }
  original_fields.clear()
  assert_true(copied.to_json() == expected)
  guard copied.to_json() is Object(wire) else {
    fail("expected details object")
  }
  guard wire.get("value") is Some(Object(value_fields)) else {
    fail("expected value object")
  }
  guard value_fields.get("nested") is Some(Array(nested)) else {
    fail("expected nested array")
  }
  nested.clear()
  value_fields.clear()
  guard wire.get("flagMetadata") is Some(Object(metadata_fields)) else {
    fail("expected metadata object")
  }
  metadata_fields.clear()
  wire.clear()
  assert_true(copied.to_json() == expected)
  assert_true(copied.metadata.get("source") == Some(Json::string("cache")))
  let error = @moonopenfeature.SdkError::new(ParseError, "invalid payload")
  let failed = @moonopenfeature.EvaluationDetails::from_resolution(
    "bad",
    @moonopenfeature.Resolution::failure(Integer(17L), error),
  )
  assert_true(failed.is_error())
  let typed : @moonopenfeature.Evaluation[Int64] = {
    value: 17L,
    details: failed,
  }
  assert_true(typed.is_error())
  assert_true(
    failed.to_json() ==
    Json::object({
      "flagKey": Json::string("bad"),
      "value": Json::number(17.0, repr="17"),
      "reason": Json::string("ERROR"),
      "flagMetadata": Json::object(Map([])),
      "errorCode": Json::string("PARSE_ERROR"),
      "errorMessage": Json::string("invalid payload"),
    }),
  )
  let minimal = @moonopenfeature.EvaluationDetails::from_resolution(
    "plain",
    @moonopenfeature.Resolution::success(Boolean(false)),
  )
  guard minimal.to_json() is Object(minimal_fields) else {
    fail("expected plain object")
  }
  assert_true(minimal_fields.get("variant") == None)
  assert_true(minimal_fields.get("errorCode") == None)
  assert_true(minimal_fields.get("errorMessage") == None)
  assert_eq(minimal_fields.length(), 4)
}
