App = ->(env) {
  body = JSON.generate(
    "request_method" => env["request_method"],
    "script_name" => env["script_name"],
    "path" => env["path"],
    "query" => env["query"],
    "probe" => env["headers"]["x-probe"],
    "body" => env["body"],
    "keys" => env.keys.sort
  )
  [200, { "content-type" => "application/json" }, [body]]
}
