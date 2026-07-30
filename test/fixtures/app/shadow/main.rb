Res = "the tenant's own"

App = ->(request) {
  [200, { "content-type" => "text/plain" }, [Res]]
}
