///|
test "evaluation options default and configured copies keep separate scope snapshots" {
  let empty = @moonopenfeature.EvaluationOptions::new()
  assert_eq(empty.context().attributes().length(), 0)
  assert_eq(empty.transaction_context().attributes().length(), 0)
  assert_eq(empty.hints().attributes().length(), 0)
  assert_true(empty.context().targeting_key() == None)
  assert_eq(empty.hooks().length(), 0)
  let items = [Json::string("original")]
  let input : Map[String, Json] = { "items": Json::array(items) }
  let base = @moonopenfeature.EvaluationContext::from_attributes(input).unwrap()
  let context = base.with_targeting_key("invocation")
  let transaction = base.with_targeting_key("transaction")
  let hints = base.with_targeting_key("hints")
  let hooks = [
    @moonopenfeature.Hook::new("one"),
    @moonopenfeature.Hook::new("two"),
  ]
  let options = @moonopenfeature.EvaluationOptions::new(
    context~,
    transaction_context=transaction,
    hooks~,
    hints~,
  )
  let copied = options.copy()
  items.clear()
  input.clear()
  hooks.clear()
  hooks.push(@moonopenfeature.Hook::new("external"))
  for current in [options, copied] {
    assert_true(current.context().targeting_key() == Some("invocation"))
    assert_true(
      current.transaction_context().targeting_key() == Some("transaction"),
    )
    assert_true(current.hints().targeting_key() == Some("hints"))
    assert_eq(current.hooks().map(hook => hook.name()), ["one", "two"])
    for
      scope in [
        current.context(),
        current.transaction_context(),
        current.hints(),
      ] {
      assert_true(
        scope.get("items") == Some(Json::array([Json::string("original")])),
      )
      guard scope.to_json() is Object(fields) else {
        fail("expected context object")
      }
      guard fields.get("items") is Some(Array(exported)) else {
        fail("expected items")
      }
      exported.clear()
      fields.clear()
      scope.attributes().clear()
    }
    let exported_hooks = current.hooks()
    exported_hooks.clear()
    exported_hooks.push(@moonopenfeature.Hook::new("injected"))
  }
  for current in [options, copied] {
    assert_eq(current.hooks().map(hook => hook.name()), ["one", "two"])
    for
      scope in [
        current.context(),
        current.transaction_context(),
        current.hints(),
      ] {
      assert_true(
        scope.get("items") == Some(Json::array([Json::string("original")])),
      )
    }
  }
  let replacement = options
    .context()
    .with_attribute("items", Json::null())
    .unwrap()
    .with_targeting_key("changed")
  assert_true(replacement.get("items") == Some(Json::null()))
  assert_true(options.context().targeting_key() == Some("invocation"))
  assert_true(copied.context().targeting_key() == Some("invocation"))
  assert_true(empty.hints().targeting_key() == None)
  assert_eq(empty.hooks().length(), 0)
}
