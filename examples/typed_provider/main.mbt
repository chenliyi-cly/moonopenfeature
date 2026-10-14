///|
fn require(condition : Bool, message : String) -> Unit {
  if !condition {
    abort(message)
  }
}

///|
fn show(label : String, details : @feature.EvaluationDetails) -> Unit {
  println(label + ": " + details.to_json().stringify())
}

///|
fn main {
  let sdk = @feature.Sdk::new()
  let client = sdk.client(name="checkout-service", version="1.0")
  sdk
  .set_context(
    @feature.EvaluationContext::from_attributes({
      "region": Json::string("sdk-region"),
      "application": Json::string("store"),
    })
    .unwrap()
    .with_targeting_key("sdk-user"),
  )
  .unwrap()
  client.set_context(
    @feature.EvaluationContext::from_attributes({
      "region": Json::string("client-region"),
      "plan": Json::string("gold"),
    })
    .unwrap()
    .with_targeting_key("client-user"),
  )
  let options = @feature.EvaluationOptions::new(
    transaction_context=@feature.EvaluationContext::from_attributes({
        "region": Json::string("transaction-region"),
        "requestId": Json::string("req-42"),
      })
      .unwrap()
      .with_targeting_key("transaction-user"),
    context=@feature.EvaluationContext::from_attributes({
        "region": Json::string("eu-west"),
        "basketSize": Json::number(3.0),
      })
      .unwrap()
      .with_targeting_key("customer-17"),
  )
  // This is application-owned configuration, injected into a callback adapter.
  // The SDK itself does not load files, contact a vendor, or invent decisions.
  let flags : Map[String, @feature.FlagValue] = {
    "order-sequence": @feature.FlagValue::Integer(9007199254740993L),
    "discount": @feature.FlagValue::Float(0.15),
    "banner": @feature.FlagValue::String("Gold delivery"),
    "shipping": @feature.FlagValue::Structure(
      Json::object({
        "methods": Json::array([
          Json::string("express"),
          Json::string("standard"),
        ]),
        "freeAbove": Json::number(50.0),
      }),
    ),
    "wrong-type": @feature.FlagValue::String("not a boolean"),
  }
  let seen : Array[@feature.EvaluationContext] = []
  let metadata = @feature.FlagMetadata::from_values({
    "source": Json::string("injected-catalog"),
    "revision": Json::number(7.0),
  }).unwrap()
  let provider = @feature.Provider::new(
    "catalog-adapter",
    (key, _, default, context) => {
      seen.push(context.copy())
      if key == "express-checkout" {
        let eligible = context.targeting_key() == Some("customer-17") &&
          context.get("plan") == Some(Json::string("gold")) &&
          context.get("region") == Some(Json::string("eu-west"))
        @feature.Resolution::success(
          @feature.FlagValue::Boolean(eligible),
          reason="TARGETING_MATCH",
          variant=Some(if eligible { "gold-eu" } else { "standard" }),
          metadata~,
        )
      } else if key == "backend-error" {
        @feature.Resolution::failure(
          default,
          @feature.SdkError::new(ParseError, "catalog revision is malformed"),
        )
      } else {
        match flags.get(key) {
          Some(value) =>
            @feature.Resolution::success(
              value.copy(),
              reason="STATIC",
              metadata~,
            )
          None =>
            @feature.Resolution::failure(
              default,
              @feature.SdkError::new(
                FlagNotFound,
                "catalog has no flag: " + key,
              ),
            )
        }
      }
    },
    // An initializer returning Ok does not imply readiness. Publish it explicitly.
    initialize=Some((_, context) => {
      println("initialize context: " + context.to_json().stringify())
      Ok(())
    }),
  )
  sdk.set_provider(provider).unwrap()
  let pending = client.boolean_details("express-checkout", false, options~)
  require(
    !pending.value &&
    pending.details.error is Some({ code: ProviderNotReady, .. }),
    "not-ready default",
  )
  require(seen.length() == 0, "not-ready calls must not reach resolver")
  show("not ready", pending.details)
  provider.emit_ready()

  let boolean = client.boolean_details("express-checkout", false, options~)
  require(boolean.value && !boolean.is_error(), "typed boolean targeting")
  show("boolean", boolean.details)
  let effective = seen[0]
  require(
    effective.targeting_key() == Some("customer-17"),
    "invocation key precedence",
  )
  require(
    effective.get("region") == Some(Json::string("eu-west")),
    "invocation attributes win",
  )
  require(
    effective.get("application") == Some(Json::string("store")),
    "SDK context retained",
  )
  require(
    effective.get("requestId") == Some(Json::string("req-42")),
    "transaction context retained",
  )
  require(
    effective.get("plan") == Some(Json::string("gold")),
    "client context retained",
  )
  println("effective context: " + effective.to_json().stringify())
  require(
    sdk.context().targeting_key() == Some("sdk-user"),
    "evaluation must not mutate SDK context",
  )
  require(
    client.context().get("region") == Some(Json::string("client-region")),
    "evaluation must not mutate client context",
  )

  let integer = client.integer_details("order-sequence", -1L, options~)
  let discount = client.float_details("discount", 0.0, options~)
  let banner = client.string_details("banner", "Safe banner", options~)
  let shipping = client.structure_details(
    "shipping",
    Json::object({}),
    options~,
  )
  require(
    integer.value == 9007199254740993L && !integer.is_error(),
    "Int64 precision",
  )
  require(discount.value == 0.15 && !discount.is_error(), "typed double")
  require(banner.value == "Gold delivery" && !banner.is_error(), "typed string")
  require(
    shipping.value == flags["shipping"].as_structure().unwrap() &&
    !shipping.is_error(),
    "typed structure",
  )
  show("integer", integer.details)
  show("float", discount.details)
  show("string", banner.details)
  show("structure", shipping.details)

  let missing = client.integer_details("missing", 42L, options~)
  let mismatch = client.boolean_details("wrong-type", false, options~)
  let failed = client.string_details("backend-error", "Safe banner", options~)
  require(
    missing.value == 42L &&
    missing.details.error is Some({ code: FlagNotFound, .. }),
    "missing flag default",
  )
  require(
    !mismatch.value &&
    mismatch.details.error is Some({ code: TypeMismatch, .. }),
    "type mismatch default",
  )
  require(
    failed.value == "Safe banner" &&
    failed.details.error is Some({ code: ParseError, .. }),
    "provider error default",
  )
  for details in [missing.details, mismatch.details, failed.details] {
    require(
      details.reason == "ERROR" && details.variant == None,
      "fallback diagnostics",
    )
  }
  show("missing default", missing.details)
  show("type mismatch default", mismatch.details)
  show("provider error default", failed.details)
  require(
    seen.length() == 8,
    "each ready evaluation must reach the injected resolver exactly once",
  )
  require(
    sdk.take_diagnostics().length() == 0,
    "evaluation errors belong in details, not observer diagnostics",
  )
  sdk.shutdown().unwrap()
}
