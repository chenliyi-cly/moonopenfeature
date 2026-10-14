///|
/// Per-hook, per-evaluation scratch data. JSON values are validated and copied;
/// unlike immutable hints, this store deliberately survives across hook stages.
/// Arbitrary MoonBit objects are not supported by this portable data contract.
pub struct HookData {
  priv entries : Map[String, Json]
}

///|
pub fn HookData::new() -> HookData {
  { entries: Map([]) }
}

///|
pub fn HookData::set(self : HookData, key : String, value : Json) -> Result[Unit, SdkError] {
  match validate_json(value) {
    Err(error) => Err(error)
    Ok(_) => {
      self.entries[key] = copy_json(value)
      Ok(())
    }
  }
}

///|
pub fn HookData::get(self : HookData, key : String) -> Json? {
  self.entries.get(key).map(copy_json)
}

///|
pub fn HookData::remove(self : HookData, key : String) -> Bool {
  let existed = self.entries.contains(key)
  self.entries.remove(key)
  existed
}

///|
pub fn HookData::keys(self : HookData) -> Array[String] {
  let keys = self.entries.keys().to_array()
  keys.sort()
  keys
}

///|
pub fn HookData::clear(self : HookData) -> Unit {
  self.entries.clear()
}
