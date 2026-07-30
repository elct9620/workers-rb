App = ->(request) {
  [200, { "content-type" => "text/plain" }, ["hello from #{request.path}\n"]]
}
