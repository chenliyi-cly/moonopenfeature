///|
pub fn Client::boolean_details(self : Client, key : String, default : Bool, options? : EvaluationOptions = EvaluationOptions::new()) -> Evaluation[Bool] {
  let details = self.evaluate(key, FlagValue::Boolean(default), options~)
  let value = match details.value { Boolean(value) => value; _ => default }
  { value, details }
}

///|
pub fn Client::boolean_value(self : Client, key : String, default : Bool, options? : EvaluationOptions = EvaluationOptions::new()) -> Bool {
  self.boolean_details(key, default, options~).value
}

///|
pub fn Client::integer_details(self : Client, key : String, default : Int64, options? : EvaluationOptions = EvaluationOptions::new()) -> Evaluation[Int64] {
  let details = self.evaluate(key, FlagValue::Integer(default), options~)
  let value = match details.value { Integer(value) => value; _ => default }
  { value, details }
}

///|
pub fn Client::integer_value(self : Client, key : String, default : Int64, options? : EvaluationOptions = EvaluationOptions::new()) -> Int64 {
  self.integer_details(key, default, options~).value
}

///|
pub fn Client::float_details(self : Client, key : String, default : Double, options? : EvaluationOptions = EvaluationOptions::new()) -> Evaluation[Double] {
  let details = self.evaluate(key, FlagValue::Float(default), options~)
  let value = match details.value { Float(value) => value; _ => default }
  { value, details }
}

///|
pub fn Client::float_value(self : Client, key : String, default : Double, options? : EvaluationOptions = EvaluationOptions::new()) -> Double {
  self.float_details(key, default, options~).value
}

///|
pub fn Client::string_details(self : Client, key : String, default : String, options? : EvaluationOptions = EvaluationOptions::new()) -> Evaluation[String] {
  let details = self.evaluate(key, FlagValue::String(default), options~)
  let value = match details.value { String(value) => value; _ => default }
  { value, details }
}

///|
pub fn Client::string_value(self : Client, key : String, default : String, options? : EvaluationOptions = EvaluationOptions::new()) -> String {
  self.string_details(key, default, options~).value
}

///|
pub fn Client::structure_details(self : Client, key : String, default : Json, options? : EvaluationOptions = EvaluationOptions::new()) -> Evaluation[Json] {
  let details = self.evaluate(key, FlagValue::Structure(default), options~)
  let value = match details.value { Structure(value) => value; _ => default }
  { value, details }
}

///|
pub fn Client::structure_value(self : Client, key : String, default : Json, options? : EvaluationOptions = EvaluationOptions::new()) -> Json {
  self.structure_details(key, default, options~).value
}
