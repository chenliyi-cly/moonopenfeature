///|
fn require(condition : Bool, message : String) -> Unit {
  if !condition {
    abort(message)
  }
}

///|
/// One hook per scope exposes the actual ordering, including error unwinding.
fn observer(name : String, trace : Array[String]) -> @feature.Hook {
  @feature.Hook::new(
    name,
    types=Some([@feature.FlagType::Boolean]),
    before=(context, hints) => {
      trace.push(name + ".before")
      require(
        context.data.get("scope") == None,
        "hook scratch data starts empty per hook and evaluation",
      )
      context.data.set("scope", Json::string(name)).unwrap()
      if name == "sdk" {
        let delta = @feature.EvaluationContext::empty()
          .with_attribute("cohort", Json::string("beta"))
          .unwrap()
          .with_attribute("traceId", hints.get("traceId").unwrap())
          .unwrap()
        Ok(Some(delta))
      } else {
        require(
          context.evaluation_context.get("cohort") == Some(Json::string("beta")),
          "earlier before-hook context must flow forward",
        )
        Ok(None)
      }
    },
    after=(context, details, _) => {
      trace.push(name + ".after")
      require(
        context.data.get("scope") == Some(Json::string(name)),
        "after stage retains only its own hook data",
      )
      require(!details.is_error(), "after sees successful details")
      require(
        context.evaluation_context.get("traceId") ==
        Some(Json::string("trace-42")),
        "after sees final context",
      )
      Ok(())
    },
    error=(context, error, _) => {
      trace.push(name + ".error:" + error.code.name())
      require(
        context.data.get("scope") == Some(Json::string(name)),
        "error stage retains per-hook data",
      )
      if name == "invocation" {
        Err(@feature.SdkError::new(General, "error observer sink unavailable"))
      } else {
        Ok(())
      }
    },
    on_finally=(context, details, _) => {
      trace.push(name + ".on_finally:" + details.reason)
      require(
        context.data.get("scope") == Some(Json::string(name)),
        "completion stage retains per-hook data",
      )
      if name == "invocation" {
        Err(
          @feature.SdkError::new(
            General,
            "completion observer sink unavailable",
          ),
        )
      } else {
        Ok(())
      }
    },
  )
}

///|
fn main {
  let sdk = @feature.Sdk::new()
  sdk
  .set_context(
    @feature.EvaluationContext::from_attributes({
      "region": Json::string("global"),
    }).unwrap(),
  )
  .unwrap()
  let client = sdk.client(domain="checkout", name="web-checkout")
  client.set_context(
    @feature.EvaluationContext::from_attributes({
      "service": Json::string("checkout"),
    })
    .unwrap()
    .with_targeting_key("customer-17"),
  )
  let trace : Array[String] = []
  let lifecycle : Array[String] = []
  let tracked : Array[@feature.TrackingEvent] = []
  let tracking_contexts : Array[@feature.EvaluationContext] = []
  let listener = sdk
    .events()
    .on(
      event => {
        let line = event.event_type.name() +
          " provider=" +
          event.provider_name +
          " domain=" +
          event.domain.unwrap()
        lifecycle.push(line)
        println("lifecycle: " + line)
        Ok(())
      },
      domain=Some("checkout"),
    )
  let provider = @feature.Provider::new(
    "observed-adapter",
    (key, _, default, context) => {
      if key == "express-checkout" {
        @feature.Resolution::success(
          @feature.FlagValue::Boolean(
            context.get("cohort") == Some(Json::string("beta")),
          ),
          reason="TARGETING_MATCH",
          variant=Some("beta"),
        )
      } else {
        @feature.Resolution::failure(
          default,
          @feature.SdkError::new(FlagNotFound, "missing flag: " + key),
        )
      }
    },
    track=Some((event, context) => {
      if event.key == "analytics-unavailable" {
        Err(@feature.SdkError::new(General, "analytics transport unavailable"))
      } else {
        tracked.push(event.copy())
        tracking_contexts.push(context.copy())
        println("tracking payload: " + event.to_json().stringify())
        println("tracking context: " + context.to_json().stringify())
        Ok(())
      }
    }),
  )
  sdk.add_hook(observer("sdk", trace))
  client.add_hook(observer("client", trace))
  provider.add_hook(observer("provider", trace))
  sdk.set_provider(provider, domain="checkout").unwrap()
  let options = @feature.EvaluationOptions::new(
    hooks=[observer("invocation", trace)],
    hints=@feature.EvaluationContext::from_attributes({
      "traceId": Json::string("trace-42"),
    }).unwrap(),
  )
  let success = client.boolean_details("express-checkout", false, options~)
  require(
    success.value && !success.is_error(),
    "observer failures must not replace successful value",
  )
  require(
    trace ==
    [
      "sdk.before", "client.before", "invocation.before", "provider.before", "provider.after",
      "invocation.after", "client.after", "sdk.after", "provider.on_finally:TARGETING_MATCH",
      "invocation.on_finally:TARGETING_MATCH", "client.on_finally:TARGETING_MATCH",
      "sdk.on_finally:TARGETING_MATCH",
    ],
    "success hook order",
  )
  println("success hooks: " + trace.join(" > "))
  println("success details: " + success.details.to_json().stringify())
  let success_diagnostics = sdk.take_diagnostics()
  require(success_diagnostics.length() == 1, "completion observer diagnostic")
  println(
    "observer diagnostic: " + success_diagnostics[0].to_json().stringify(),
  )

  trace.clear()
  let missing = client.boolean_details("missing", false, options~)
  require(
    !missing.value && missing.details.error is Some({ code: FlagNotFound, .. }),
    "original evaluation error must survive observer errors",
  )
  require(
    trace ==
    [
      "sdk.before", "client.before", "invocation.before", "provider.before", "provider.error:FLAG_NOT_FOUND",
      "invocation.error:FLAG_NOT_FOUND", "client.error:FLAG_NOT_FOUND", "sdk.error:FLAG_NOT_FOUND",
      "provider.on_finally:ERROR", "invocation.on_finally:ERROR", "client.on_finally:ERROR",
      "sdk.on_finally:ERROR",
    ],
    "error hook order and continued unwinding",
  )
  println("error hooks: " + trace.join(" > "))
  println("error details: " + missing.details.to_json().stringify())
  let error_diagnostics = sdk.take_diagnostics()
  require(
    error_diagnostics.length() == 2,
    "both broken observers must be diagnosed",
  )
  for diagnostic in error_diagnostics {
    println("observer diagnostic: " + diagnostic.to_json().stringify())
  }
  require(sdk.take_diagnostics().length() == 0, "diagnostics drain once")
  require(
    client.context().get("cohort") == None,
    "hook context must not persist in client",
  )

  trace.clear()
  let details = @feature.EvaluationContext::from_attributes({
    "orderId": Json::string("order-42"),
    "items": Json::array([Json::string("book"), Json::string("pen")]),
  }).unwrap()
  let event = @feature.TrackingEvent::new(
    "purchase",
    value=Some(79.5),
    details~,
  ).unwrap()
  client
  .track_checked(
    event,
    transaction_context=@feature.EvaluationContext::from_attributes({
      "requestId": Json::string("req-42"),
    }).unwrap(),
    context=@feature.EvaluationContext::from_attributes({
      "region": Json::string("eu-west"),
    }).unwrap(),
  )
  .unwrap()
  require(
    tracked.length() == 1 && tracked[0].value == Some(79.5),
    "tracking callback records payload",
  )
  require(
    tracking_contexts[0].targeting_key() == Some("customer-17"),
    "tracking merges client targeting key",
  )
  require(
    tracking_contexts[0].get("requestId") == Some(Json::string("req-42")),
    "tracking transaction context",
  )
  require(
    tracking_contexts[0].get("cohort") == None && trace.length() == 0,
    "tracking is not evaluation and must not run hooks",
  )
  let failed_track = client.track_checked(
    @feature.TrackingEvent::new("analytics-unavailable").unwrap(),
  )
  require(
    failed_track is Err({ code: General, .. }),
    "tracking error propagates explicitly",
  )
  println(
    "tracking failure: " + failed_track.unwrap_err().to_json().stringify(),
  )
  provider.emit_configuration_changed(["express-checkout"])
  require(
    lifecycle.length() == 2,
    "ready and configuration-change observability",
  )
  require(sdk.events().off(listener), "remove lifecycle listener")
  require(
    sdk.take_diagnostics().length() == 0,
    "tracking errors are returned, not observer diagnostics",
  )
  // Standard Unit tracking never throws; failures remain observable via SDK diagnostics.
  client.track(@feature.TrackingEvent::new("analytics-unavailable").unwrap())
  let no_throw_diagnostics = sdk.take_diagnostics()
  require(
    no_throw_diagnostics.length() == 1 &&
    no_throw_diagnostics[0].code == @feature.ErrorCode::General,
    "Unit tracking preserves diagnostics",
  )
  println(
    "no-throw tracking diagnostic: " +
    no_throw_diagnostics[0].to_json().stringify(),
  )
  require(
    trace.length() == 0 && tracked.length() == 1,
    "failed tracking must not run evaluation hooks or record a purchase",
  )
  require(
    sdk.take_diagnostics().length() == 0,
    "tracking diagnostics drain once",
  )
  sdk.shutdown().unwrap()
}
