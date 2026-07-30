App = ->(request) {
  body = JSON.generate(
    "request_method" => request.request_method,
    "script_name" => request.script_name,
    "path" => request.path,
    "query" => request.query,
    "probe" => request.headers["x-probe"],
    "body" => request.body
  )
  [200, { "content-type" => "application/json" }, [body]]
}
