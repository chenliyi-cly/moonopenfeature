///|
test "standard errors and open reason names" {
  for
    code in [
      @moonopenfeature.ErrorCode::ProviderNotReady,
      ProviderFatal,
      FlagNotFound,
      ParseError,
      TypeMismatch,
      TargetingKeyMissing,
      InvalidContext,
      General,
    ] {
    assert_true(@moonopenfeature.ErrorCode::parse(code.name()) == Some(code))
  }
  assert_true(@moonopenfeature.ErrorCode::parse("vendor-error") == None)
  for
    reason in [
      @moonopenfeature.StandardReason::Static,
      Default,
      TargetingMatch,
      Split,
      Cached,
      Disabled,
      Unknown,
      Stale,
      Error,
    ] {
    assert_true(
      @moonopenfeature.StandardReason::parse(reason.name()) == Some(reason),
    )
  }
  assert_true(@moonopenfeature.StandardReason::parse("vendor-reason") == None)
}

///|
test "non ready and fatal prevent evaluation but error and stale permit it" {
  assert_true(
    @moonopenfeature.ProviderStatus::NotReady.evaluation_error() is Some(_),
  )
  assert_true(
    @moonopenfeature.ProviderStatus::Shutdown.evaluation_error() is Some(_),
  )
  assert_true(
    @moonopenfeature.ProviderStatus::Fatal.evaluation_error()
    is Some({ code: ProviderFatal, .. }),
  )
  assert_true(@moonopenfeature.ProviderStatus::Ready.evaluation_error() == None)
  assert_true(@moonopenfeature.ProviderStatus::Stale.evaluation_error() == None)
  assert_true(@moonopenfeature.ProviderStatus::Error.evaluation_error() == None)
}
