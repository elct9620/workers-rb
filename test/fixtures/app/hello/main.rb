App = ->(env) {
  [200, { "content-type" => "text/plain" }, ["hello from #{env["path"]}\n"]]
}
