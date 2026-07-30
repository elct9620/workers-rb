Response = "the tenant's own"

App = ->(env) {
  [200, { "content-type" => "text/plain" }, [Response]]
}
