App = ->(env) {
  body = JSON.generate(
    "time" => Time.now,
    "roll" => Random.rand(6),
    "unit" => Random.rand,
    "matched" => (env["path"] =~ /\A\/dice/) == 0
  )
  [200, { "content-type" => "application/json" }, [body]]
}
