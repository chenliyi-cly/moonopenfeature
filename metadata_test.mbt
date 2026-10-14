///|
test "flag metadata rejects objects, nulls and nonfinite numbers" {
  assert_true(
    @moonopenfeature.FlagMetadata::from_values({ "n": Json::null() }) is Err(_),
  )
  assert_true(
    @moonopenfeature.FlagMetadata::from_values({ "o": Json::object({}) })
    is Err(_),
  )
  assert_true(
    @moonopenfeature.FlagMetadata::from_values({ "x": Json::number(1.0 / 0.0) })
    is Err(_),
  )
  assert_true(
    @moonopenfeature.FlagMetadata::from_values({ "x": Json::number(0.0 / 0.0) })
    is Err(_),
  )
}

///|
test "metadata snapshots and scalar overlay are independent" {
  let input = { "engine": Json::string("one"), "enabled": Json::boolean(true) }
  let first = match @moonopenfeature.FlagMetadata::from_values(input) {
    Ok(m) => m
    Err(_) => abort("valid metadata")
  }
  input["engine"] = Json::string("mutated")
  assert_true(first.get("engine") == Some(Json::string("one")))
  let exposed = first.values()
  exposed.clear()
  assert_true(first.get("enabled") == Some(Json::boolean(true)))
  let second = match first.with_value("engine", Json::string("two")) {
    Ok(m) => m
    Err(_) => abort("valid metadata")
  }
  assert_true(first.get("engine") == Some(Json::string("one")))
  assert_true(first.merge(second).get("engine") == Some(Json::string("two")))
}

///|
test "metadata validates raw numeric representation and preserves exact integers" {
  let bad = Json::number(1.0, repr="not-json")
  try! assert_true(@moonopenfeature.validate_json(bad) is Err(_))
  try! assert_true(@moonopenfeature.FlagMetadata::from_values({ "bad": bad }) is Err(_))
  let good = @moonopenfeature.FlagMetadata::from_values({
    "large": Json::number(9007199254740992.0, repr="9007199254740993")
  }).unwrap()
  try! assert_eq(good.to_json().stringify(), "{\"large\":9007199254740993}")
  try! assert_true(@moonopenfeature.validate_json(good.to_json()) is Ok(_))
  try! assert_true(good.with_value("bad", bad) is Err(_))
  try! assert_eq(good.values().length(), 1)
}
