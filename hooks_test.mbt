///|
fn hooks_test_context() -> @moonopenfeature.HookContext {
  {
    flag_key: "feature",
    flag_type: Boolean,
    default_value: Boolean(false),
    evaluation_context: @moonopenfeature.EvaluationContext::empty().with_targeting_key(
      "base",
    ),
    client: { name: "client", version: "1.0", domain: "tenant", },
    provider_name: "provider",
    data: @moonopenfeature.HookData::new(),
  }
}

///|
fn hooks_test_ordered(
  name : String,
  seen : Array[String],
) -> @moonopenfeature.Hook {
  @moonopenfeature.Hook::new(
    name,
    before=(context, _) => {
      seen.push(
        "before:" +
        name +
        ":" +
        context.evaluation_context.targeting_key().unwrap_or("missing"),
      )
      let additional = @moonopenfeature.EvaluationContext::empty()
        .with_targeting_key(name)
        .with_attribute(name, Json::boolean(true))
        .unwrap()
      Ok(Some(additional))
    },
    after=(_, _, _) => {
      seen.push("after:" + name)
      Ok(())
    },
    error=(_, _, _) => {
      seen.push("error:" + name)
      Ok(())
    },
    on_finally=(_, _, _) => {
      seen.push("finally:" + name)
      Ok(())
    },
  )
}

///|
test "hook filtering snapshots type arrays scopes and published names" {
  let types : Array[@moonopenfeature.FlagType] = [Boolean, Integer]
  let restricted = @moonopenfeature.Hook::new("restricted", types=Some(types))
  let all = @moonopenfeature.Hook::new("all")
  let never = @moonopenfeature.Hook::new("never", types=Some([]))
  let strings = @moonopenfeature.Hook::new("string", types=Some([String]))
  types.clear()
  types.push(Float)
  assert_eq(restricted.name(), "restricted")
  for
    kind in [
      @moonopenfeature.FlagType::Boolean,
      Integer,
      Float,
      String,
      Structure,
    ] {
    assert_true(all.supports(kind))
    assert_true(!never.supports(kind))
    assert_true(
      restricted.supports(kind) == (kind == Boolean || kind == Integer),
    )
    assert_true(strings.supports(kind) == (kind == String))
  }
  let api = [all, never]
  let client = [restricted]
  let invocation = [strings]
  let provider = [@moonopenfeature.Hook::new("provider")]
  let boolean_plan = @moonopenfeature.HookPlan::new(
    Boolean,
    api,
    client,
    invocation,
    provider,
  )
  let string_plan = @moonopenfeature.HookPlan::new(
    String,
    api,
    client,
    invocation,
    provider,
  )
  api.clear()
  client.clear()
  invocation.clear()
  provider.clear()
  assert_eq(boolean_plan.names(), ["all", "restricted", "provider"])
  assert_eq(boolean_plan.length(), 3)
  assert_eq(string_plan.names(), ["all", "string", "provider"])
  let names = boolean_plan.names()
  names.clear()
  assert_eq(boolean_plan.names(), ["all", "restricted", "provider"])
  let empty = @moonopenfeature.HookPlan::new(Boolean, [], [], [], [])
  let context = hooks_test_context()
  let hints = @moonopenfeature.EvaluationContext::empty()
  let details = @moonopenfeature.EvaluationDetails::from_resolution(
    "feature",
    @moonopenfeature.Resolution::success(Boolean(true)),
  )
  let before = empty.before(context, hints)
  assert_true(before.error == None)
  assert_true(before.context.targeting_key() == Some("base"))
  assert_true(empty.after(context, details, hints) is Ok(_))
  assert_eq(
    empty
    .on_error(
      context,
      @moonopenfeature.SdkError::new(General, "evaluation"),
      hints,
    )
    .length(),
    0,
  )
  assert_eq(empty.run_finally(context, details, hints).length(), 0)
}

///|
test "hook scope order merges before forward and runs after error finally reverse" {
  let seen : Array[String] = []
  let names = [
    "api-one", "api-two", "client-one", "client-two", "invocation-one", "invocation-two",
    "provider-one", "provider-two",
  ]
  let hooks = names.map(name => hooks_test_ordered(name, seen))
  let api = [hooks[0], hooks[1]]
  let client = [hooks[2], hooks[3]]
  let invocation = [hooks[4], hooks[5]]
  let provider = [hooks[6], hooks[7]]
  let plan = @moonopenfeature.HookPlan::new(
    Boolean,
    api,
    client,
    invocation,
    provider,
  )
  let context = hooks_test_context()
  let hints = @moonopenfeature.EvaluationContext::empty()
  let before = plan.before(context, hints)
  assert_true(before.error == None)
  assert_true(before.context.targeting_key() == Some("provider-two"))
  for name in names {
    assert_true(before.context.get(name) == Some(Json::boolean(true)))
  }
  assert_eq(context.evaluation_context.attributes().length(), 0)
  assert_true(context.evaluation_context.targeting_key() == Some("base"))
  assert_eq(seen, [
    "before:api-one:base", "before:api-two:api-one", "before:client-one:api-two",
    "before:client-two:client-one", "before:invocation-one:client-two", "before:invocation-two:invocation-one",
    "before:provider-one:invocation-two", "before:provider-two:provider-one",
  ])
  seen.clear()
  api.clear()
  client.clear()
  invocation.clear()
  provider.clear()
  let details = @moonopenfeature.EvaluationDetails::from_resolution(
    "feature",
    @moonopenfeature.Resolution::success(Boolean(true)),
  )
  let current = context.with_context(before.context)
  assert_true(plan.after(current, details, hints) is Ok(_))
  assert_eq(
    plan
    .on_error(
      current,
      @moonopenfeature.SdkError::new(General, "evaluation"),
      hints,
    )
    .length(),
    0,
  )
  assert_eq(plan.run_finally(current, details, hints).length(), 0)
  let expected : Array[String] = []
  for phase in ["after", "error", "finally"] {
    for index = names.length() - 1; index >= 0; index = index - 1 {
      expected.push(phase + ":" + names[index])
    }
  }
  assert_eq(seen, expected)
  assert_eq(plan.names(), names)
  assert_eq(plan.length(), 8)
}

///|
test "hook before abort retains earlier merge and after failure stops reverse chain" {
  let seen : Array[String] = []
  let before_error = @moonopenfeature.SdkError::new(
    InvalidContext,
    "before failed",
  )
  let after_error = @moonopenfeature.SdkError::new(General, "after failed")
  let api = hooks_test_ordered("api", seen)
  let client = @moonopenfeature.Hook::new(
    "client",
    before=(context, _) => {
      seen.push(
        "before:client:" +
        context.evaluation_context.targeting_key().unwrap_or("missing"),
      )
      try! assert_true(
        context.data.set("attempt", Json::string("before-abort")) is Ok(_),
      )
      Err(before_error)
    },
    after=(context, _, _) => {
      try! assert_true(
        context.data.get("attempt") == Some(Json::string("before-abort")),
      )
      try! assert_true(
        context.data.set("failed-after", Json::boolean(true)) is Ok(_),
      )
      seen.push("after:client")
      Err(after_error)
    },
    error=(context, _, _) => {
      try! assert_true(
        context.data.get("attempt") == Some(Json::string("before-abort")),
      )
      try! assert_true(
        context.data.get("failed-after") == Some(Json::boolean(true)),
      )
      try! assert_true(
        context.data.set("observed-error", Json::boolean(true)) is Ok(_),
      )
      seen.push("error:client")
      Ok(())
    },
    on_finally=(context, _, _) => {
      try! assert_true(
        context.data.get("attempt") == Some(Json::string("before-abort")),
      )
      try! assert_true(
        context.data.get("failed-after") == Some(Json::boolean(true)),
      )
      try! assert_true(
        context.data.get("observed-error") == Some(Json::boolean(true)),
      )
      seen.push("finally:client")
      Ok(())
    },
  )
  let plan = @moonopenfeature.HookPlan::new(
    Boolean,
    [api],
    [client],
    [hooks_test_ordered("invocation", seen)],
    [hooks_test_ordered("provider", seen)],
  )
  let context = hooks_test_context()
  let hints = @moonopenfeature.EvaluationContext::empty()
  let before = plan.before(context, hints)
  assert_true(before.error == Some(before_error))
  assert_true(before.context.targeting_key() == Some("api"))
  assert_true(before.context.get("api") == Some(Json::boolean(true)))
  assert_true(before.context.get("invocation") == None)
  assert_true(before.context.get("provider") == None)
  assert_eq(seen, ["before:api:base", "before:client:api"])
  assert_true(context.evaluation_context.targeting_key() == Some("base"))
  seen.clear()
  let details = @moonopenfeature.EvaluationDetails::from_resolution(
    "feature",
    @moonopenfeature.Resolution::success(Boolean(true)),
  )
  assert_true(
    plan.after(context, details, hints) is Err(error) && error == after_error,
  )
  assert_eq(seen, ["after:provider", "after:invocation", "after:client"])
  seen.clear()
  assert_eq(plan.on_error(context, before_error, hints).length(), 0)
  assert_eq(plan.run_finally(context, details, hints).length(), 0)
  assert_eq(seen, [
    "error:provider", "error:invocation", "error:client", "error:api", "finally:provider",
    "finally:invocation", "finally:client", "finally:api",
  ])
}

///|
fn hooks_test_mutate_inputs(
  context : @moonopenfeature.HookContext,
  hints : @moonopenfeature.EvaluationContext,
) -> Unit {
  try! assert_eq(context.flag_key, "structured")
  try! assert_eq(context.client.name, "client")
  try! assert_eq(context.client.version, "1.0")
  try! assert_eq(context.client.domain, "tenant")
  try! assert_eq(context.provider_name, "provider")
  try! assert_true(
    context.default_value.to_json() == Json::array([Json::string("default")]),
  )
  guard context.default_value is Structure(Array(default_items)) else {
    try! fail("default missing")
  }
  default_items.clear()
  try! assert_true(
    context.evaluation_context.get("items") ==
    Some(Json::array([Json::string("context")])),
  )
  guard context.evaluation_context.to_json() is Object(context_fields) else {
    try! fail("context missing")
  }
  guard context_fields.get("items") is Some(Array(context_items)) else {
    try! fail("context items missing")
  }
  context_items.clear()
  context_fields.clear()
  try! assert_true(
    hints.get("items") == Some(Json::array([Json::string("hint")])),
  )
  guard hints.to_json() is Object(hint_fields) else {
    try! fail("hints missing")
  }
  guard hint_fields.get("items") is Some(Array(hint_items)) else {
    try! fail("hint items missing")
  }
  hint_items.clear()
  hint_fields.clear()
}

///|
fn hooks_test_mutate_details(
  details : @moonopenfeature.EvaluationDetails,
) -> Unit {
  try! assert_eq(details.flag_key, "structured")
  try! assert_eq(details.reason, "STATIC")
  try! assert_true(details.variant == Some("variant"))
  try! assert_true(
    details.value.to_json() ==
    Json::object({ "items": Json::array([Json::string("resolved")]) }),
  )
  try! assert_true(
    details.metadata.get("source") == Some(Json::string("provider")),
  )
  guard details.value is Structure(Object(fields)) else {
    try! fail("resolution object missing")
  }
  guard fields.get("items") is Some(Array(items)) else {
    try! fail("resolution items missing")
  }
  items.clear()
  fields.clear()
  guard details.to_json() is Object(wire) else {
    try! fail("details wire missing")
  }
  guard wire.get("flagMetadata") is Some(Object(metadata)) else {
    try! fail("metadata missing")
  }
  metadata.clear()
  wire.clear()
}

///|
test "hook callbacks isolate mutable JSON while observer errors continue and collect in reverse" {
  let context : @moonopenfeature.HookContext = {
    ..hooks_test_context(),
    flag_key: "structured",
    flag_type: Structure,
    default_value: Structure(Json::array([Json::string("default")])),
    evaluation_context: @moonopenfeature.EvaluationContext::empty()
    .with_attribute("items", Json::array([Json::string("context")]))
    .unwrap(),
  }
  let hints = @moonopenfeature.EvaluationContext::empty()
    .with_attribute("items", Json::array([Json::string("hint")]))
    .unwrap()
  let metadata = @moonopenfeature.FlagMetadata::from_values({
    "source": Json::string("provider"),
  }).unwrap()
  let details = @moonopenfeature.EvaluationDetails::from_resolution(
    "structured",
    @moonopenfeature.Resolution::success(
      Structure(
        Json::object({ "items": Json::array([Json::string("resolved")]) }),
      ),
      reason="STATIC",
      variant=Some("variant"),
      metadata~,
    ),
  )
  let expected_details = details.to_json()
  let copied_context = context.copy()
  guard copied_context.default_value is Structure(Array(copied_items)) else {
    fail("copy default missing")
  }
  copied_items.clear()
  assert_true(
    context.default_value.to_json() == Json::array([Json::string("default")]),
  )
  let replacement = context.with_context(
    context.evaluation_context.with_targeting_key("replacement"),
  )
  assert_true(
    replacement.evaluation_context.targeting_key() == Some("replacement"),
  )
  assert_true(context.evaluation_context.targeting_key() == None)
  guard replacement.default_value is Structure(Array(replacement_items)) else {
    fail("replacement default missing")
  }
  replacement_items.clear()
  assert_true(
    context.default_value.to_json() == Json::array([Json::string("default")]),
  )
  let seen : Array[String] = []
  let evaluation_error = @moonopenfeature.SdkError::new(FlagNotFound, "missing")
  let hooks = ["api", "client", "provider"].map(name => {
    @moonopenfeature.Hook::new(
      name,
      before=(current, current_hints) => {
        hooks_test_mutate_inputs(current, current_hints)
        seen.push("before:" + name)
        Ok(None)
      },
      after=(current, current_details, current_hints) => {
        hooks_test_mutate_inputs(current, current_hints)
        hooks_test_mutate_details(current_details)
        seen.push("after:" + name)
        Ok(())
      },
      error=(current, error, current_hints) => {
        hooks_test_mutate_inputs(current, current_hints)
        try! assert_true(error == evaluation_error)
        seen.push("error:" + name)
        if name == "client" {
          Ok(())
        } else {
          Err(@moonopenfeature.SdkError::new(General, "error-observer:" + name))
        }
      },
      on_finally=(current, current_details, current_hints) => {
        hooks_test_mutate_inputs(current, current_hints)
        hooks_test_mutate_details(current_details)
        seen.push("finally:" + name)
        if name == "client" {
          Ok(())
        } else {
          Err(
            @moonopenfeature.SdkError::new(General, "finally-observer:" + name),
          )
        }
      },
    )
  })
  let plan = @moonopenfeature.HookPlan::new(
    Structure,
    [hooks[0]],
    [hooks[1]],
    [],
    [hooks[2]],
  )
  let before = plan.before(context, hints)
  assert_true(before.error == None)
  assert_true(before.context.to_json() == context.evaluation_context.to_json())
  assert_true(plan.after(context, details, hints) is Ok(_))
  let errors = plan.on_error(context, evaluation_error, hints)
  let final_errors = plan.run_finally(context, details, hints)
  assert_eq(errors.map(error => error.message), [
    "error-observer:provider", "error-observer:api",
  ])
  assert_eq(final_errors.map(error => error.message), [
    "finally-observer:provider", "finally-observer:api",
  ])
  for error in errors {
    assert_true(error.code == General)
  }
  for error in final_errors {
    assert_true(error.code == General)
  }
  assert_eq(seen, [
    "before:api", "before:client", "before:provider", "after:provider", "after:client",
    "after:api", "error:provider", "error:client", "error:api", "finally:provider",
    "finally:client", "finally:api",
  ])
  assert_true(
    context.default_value.to_json() == Json::array([Json::string("default")]),
  )
  assert_true(
    context.evaluation_context.get("items") ==
    Some(Json::array([Json::string("context")])),
  )
  assert_true(hints.get("items") == Some(Json::array([Json::string("hint")])))
  assert_true(details.to_json() == expected_details)
  assert_true(details.metadata.get("source") == Some(Json::string("provider")))
  assert_true(!details.is_error())
}

///|
test "hook data persists by stage but never leaks between hooks or evaluation plans" {
  let retained : Array[@moonopenfeature.HookData] = []
  let seen : Array[String] = []
  let hooks = ["api", "provider"].map(name => {
    @moonopenfeature.Hook::new(
      name,
      before=(current, _) => {
        let evaluation = current.evaluation_context
          .targeting_key()
          .unwrap_or("missing")
        try! assert_eq(current.data.keys().length(), 0)
        try! assert_true(current.data.set("owner", Json::string(name)) is Ok(_))
        try! assert_true(
          current.data.set("evaluation", Json::string(evaluation)) is Ok(_),
        )
        try! assert_true(
          current.data.set("stage", Json::string("before")) is Ok(_),
        )
        retained.push(current.data)
        seen.push("before:" + evaluation + ":" + name)
        Ok(None)
      },
      after=(current, _, _) => {
        let evaluation = current.evaluation_context
          .targeting_key()
          .unwrap_or("missing")
        try! assert_true(current.data.get("owner") == Some(Json::string(name)))
        try! assert_true(
          current.data.get("evaluation") == Some(Json::string(evaluation)),
        )
        try! assert_true(
          current.data.get("stage") == Some(Json::string("before")),
        )
        try! assert_true(
          current.data.get("external") ==
          (if evaluation == "one" && name == "api" {
            Some(Json::boolean(true))
          } else {
            None
          }),
        )
        try! assert_true(
          current.data.set("stage", Json::string("after")) is Ok(_),
        )
        seen.push("after:" + evaluation + ":" + name)
        Ok(())
      },
      error=(current, _, _) => {
        let evaluation = current.evaluation_context
          .targeting_key()
          .unwrap_or("missing")
        try! assert_true(current.data.get("owner") == Some(Json::string(name)))
        try! assert_true(
          current.data.get("evaluation") == Some(Json::string(evaluation)),
        )
        try! assert_true(
          current.data.get("stage") == Some(Json::string("after")),
        )
        try! assert_true(
          current.data.set("stage", Json::string("error")) is Ok(_),
        )
        seen.push("error:" + evaluation + ":" + name)
        Ok(())
      },
      on_finally=(current, _, _) => {
        let evaluation = current.evaluation_context
          .targeting_key()
          .unwrap_or("missing")
        try! assert_true(current.data.get("owner") == Some(Json::string(name)))
        try! assert_true(
          current.data.get("evaluation") == Some(Json::string(evaluation)),
        )
        try! assert_true(
          current.data.get("stage") == Some(Json::string("error")),
        )
        try! assert_true(
          current.data.set("stage", Json::string("finally")) is Ok(_),
        )
        seen.push("finally:" + evaluation + ":" + name)
        Ok(())
      },
    )
  })
  let first = @moonopenfeature.HookPlan::new(Boolean, [hooks[0]], [], [], [
    hooks[1],
  ])
  let second = @moonopenfeature.HookPlan::new(Boolean, [hooks[0]], [], [], [
    hooks[1],
  ])
  let base = hooks_test_context()
  assert_true(base.data.set("caller", Json::boolean(true)) is Ok(_))
  let one = base.with_context(base.evaluation_context.with_targeting_key("one"))
  let two = base.with_context(base.evaluation_context.with_targeting_key("two"))
  let hints = @moonopenfeature.EvaluationContext::empty()
  let details = @moonopenfeature.EvaluationDetails::from_resolution(
    "feature",
    @moonopenfeature.Resolution::success(Boolean(true)),
  )
  assert_true(first.before(one, hints).error == None)
  assert_true(second.before(two, hints).error == None)
  assert_eq(retained.length(), 4)
  assert_true(retained[0].set("external", Json::boolean(true)) is Ok(_))
  assert_true(retained[1].get("external") == None)
  assert_true(retained[2].get("external") == None)
  assert_true(retained[3].get("external") == None)
  // Interleave stages: evaluating plan two must not change plan one's store.
  assert_true(second.after(two, details, hints) is Ok(_))
  assert_true(retained[0].get("stage") == Some(Json::string("before")))
  assert_true(first.after(one, details, hints) is Ok(_))
  let error = @moonopenfeature.SdkError::new(General, "evaluation failure")
  assert_eq(first.on_error(one, error, hints).length(), 0)
  assert_eq(second.on_error(two, error, hints).length(), 0)
  assert_eq(second.run_finally(two, details, hints).length(), 0)
  assert_true(retained[0].get("stage") == Some(Json::string("error")))
  assert_eq(first.run_finally(one, details, hints).length(), 0)
  for data in retained {
    assert_true(data.get("stage") == Some(Json::string("finally")))
  }
  assert_eq(base.data.keys(), ["caller"])
  assert_true(base.data.get("caller") == Some(Json::boolean(true)))
  assert_eq(seen, [
    "before:one:api", "before:one:provider", "before:two:api", "before:two:provider",
    "after:two:provider", "after:two:api", "after:one:provider", "after:one:api",
    "error:one:provider", "error:one:api", "error:two:provider", "error:two:api",
    "finally:two:provider", "finally:two:api", "finally:one:provider", "finally:one:api",
  ])
}

///|
test "hook data bounded JSON writes are atomic and accessors cannot alias nested storage" {
  let data = @moonopenfeature.HookData::new()
  assert_eq(data.keys(), [])
  assert_true(data.get("missing") == None)
  assert_true(!data.remove("missing"))
  let items = [Json::string("original")]
  let fields : Map[String, Json] = { "nested": Json::array(items) }
  assert_true(data.set("z", Json::object(fields)) is Ok(_))
  assert_true(data.set("a", Json::number(2.0)) is Ok(_))
  assert_true(data.set("", Json::null()) is Ok(_))
  items.clear()
  fields.clear()
  let expected = Json::object({
    "nested": Json::array([Json::string("original")]),
  })
  assert_true(data.get("z") == Some(expected))
  guard data.get("z") is Some(Object(exported_fields)) else {
    fail("expected stored object")
  }
  guard exported_fields.get("nested") is Some(Array(exported_items)) else {
    fail("expected stored array")
  }
  exported_items.clear()
  exported_fields.clear()
  assert_true(data.get("z") == Some(expected))
  assert_eq(data.keys(), ["", "a", "z"])
  data.keys().clear()
  assert_eq(data.keys(), ["", "a", "z"])
  for number in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(
      data.set("z", Json::number(number)) is Err({ code: InvalidContext, .. }),
    )
    assert_true(data.get("z") == Some(expected))
  }
  let mut deep = Json::null()
  for _ in 0..<65 {
    deep = Json::array([deep])
  }
  assert_true(data.set("too-deep", deep) is Err({ code: InvalidContext, .. }))
  assert_true(data.get("too-deep") == None)
  let cycle : Array[Json] = []
  let cyclic = Json::array(cycle)
  cycle.push(cyclic)
  assert_true(data.set("cyclic", cyclic) is Err({ code: InvalidContext, .. }))
  assert_true(data.get("cyclic") == None)
  assert_eq(data.keys(), ["", "a", "z"])
  assert_true(data.remove("a"))
  assert_true(!data.remove("a"))
  assert_eq(data.keys(), ["", "z"])
  data.clear()
  assert_eq(data.keys(), [])
  assert_true(data.get("z") == None)
}
