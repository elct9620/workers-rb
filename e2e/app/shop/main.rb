# The same Worker as `where`, published under a domain its Manifest declares
# rather than under the cluster's own — so what the two answers differ in is
# the routing form, and nothing else.
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
