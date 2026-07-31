# Says which Node answered and where that Node decided the Worker was mounted.
App = ->(env) {
  req = Request.new(env)

  Response.json({
    "tenant" => Env.tenant,
    "node" => Env.node,
    "writer" => Env.writer?,
    "script_name" => req.script_name,
    "path" => req.path
  })
}
