///|
/// Standard errors plus a bounded-input extension. Provider errors never escape as exceptions.
pub(all) enum ErrorCode {
  ProviderNotReady
  ProviderFatal
  FlagNotFound
  ParseError
  TypeMismatch
  TargetingKeyMissing
  InvalidContext
  General
} derive(Eq)

///|
pub fn ErrorCode::name(self : ErrorCode) -> String {
  match self {
    ProviderNotReady => "PROVIDER_NOT_READY"
    ProviderFatal => "PROVIDER_FATAL"
    FlagNotFound => "FLAG_NOT_FOUND"
    ParseError => "PARSE_ERROR"
    TypeMismatch => "TYPE_MISMATCH"
    TargetingKeyMissing => "TARGETING_KEY_MISSING"
    InvalidContext => "INVALID_CONTEXT"
    General => "GENERAL"
  }
}

///|
pub fn ErrorCode::parse(name : String) -> ErrorCode? {
  match name {
    "PROVIDER_NOT_READY" => Some(ProviderNotReady)
    "PROVIDER_FATAL" => Some(ProviderFatal)
    "FLAG_NOT_FOUND" => Some(FlagNotFound)
    "PARSE_ERROR" => Some(ParseError)
    "TYPE_MISMATCH" => Some(TypeMismatch)
    "TARGETING_KEY_MISSING" => Some(TargetingKeyMissing)
    "INVALID_CONTEXT" => Some(InvalidContext)
    "GENERAL" => Some(General)
    _ => None
  }
}

///|
pub(all) struct SdkError {
  code : ErrorCode
  message : String
} derive(Eq)

///|
pub fn SdkError::new(code : ErrorCode, message : String) -> SdkError {
  { code, message, }
}

///|
pub fn SdkError::to_json(self : SdkError) -> Json {
  Json::object({
    "code": Json::string(self.code.name()),
    "message": Json::string(self.message),
  })
}

///|
/// Reasons are open strings in OpenFeature. These helpers name standard reasons
/// without discarding provider-defined extensions.
pub(all) enum StandardReason {
  Static
  Default
  TargetingMatch
  Split
  Cached
  Disabled
  Unknown
  Stale
  Error
} derive(Eq)

///|
pub fn StandardReason::name(self : StandardReason) -> String {
  match self {
    Static => "STATIC"
    Default => "DEFAULT"
    TargetingMatch => "TARGETING_MATCH"
    Split => "SPLIT"
    Cached => "CACHED"
    Disabled => "DISABLED"
    Unknown => "UNKNOWN"
    Stale => "STALE"
    Error => "ERROR"
  }
}

///|
pub fn StandardReason::parse(name : String) -> StandardReason? {
  match name {
    "STATIC" => Some(Static)
    "DEFAULT" => Some(Default)
    "TARGETING_MATCH" => Some(TargetingMatch)
    "SPLIT" => Some(Split)
    "CACHED" => Some(Cached)
    "DISABLED" => Some(Disabled)
    "UNKNOWN" => Some(Unknown)
    "STALE" => Some(Stale)
    "ERROR" => Some(Error)
    _ => None
  }
}

///|
/// Lifecycle states are deliberately distinct from the last evaluation error.
pub(all) enum ProviderStatus {
  NotReady
  Ready
  Stale
  Error
  Fatal
  Shutdown
} derive(Eq)

///|
pub fn ProviderStatus::name(self : ProviderStatus) -> String {
  match self {
    NotReady => "NOT_READY"
    Ready => "READY"
    Stale => "STALE"
    Error => "ERROR"
    Fatal => "FATAL"
    Shutdown => "SHUTDOWN"
  }
}

///|
pub fn ProviderStatus::evaluation_error(self : ProviderStatus) -> SdkError? {
  match self {
    NotReady | Shutdown =>
      Some(SdkError::new(ProviderNotReady, "provider is not ready"))
    Fatal => Some(SdkError::new(ProviderFatal, "provider is fatal"))
    Ready | Stale | Error => None
  }
}

///|
pub extend ErrorCode with Eq::{equal, not_equal}

///|
pub extend SdkError with Eq::{equal, not_equal}

///|
pub extend StandardReason with Eq::{equal, not_equal}

///|
pub extend ProviderStatus with Eq::{equal, not_equal}
