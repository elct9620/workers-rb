App = ->(env) {
  body = JSON.generate(
    "node" => Env.node,
    "tenant" => Env.tenant,
    "request_id" => Env.request_id,
    # Asked twice within one invocation; the identity is the invocation's, not
    # the question's.
    "stable" => Env.request_id == Env.request_id
  )
  [200, { "content-type" => "application/json" }, [body]]
}
