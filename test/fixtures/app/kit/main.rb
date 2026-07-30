App = ->(env) {
  req = Request.new(env)

  case req.path
  when "/text"
    Response.text("plain")
  when "/json"
    Response.json({ "shaped" => true })
  when "/status"
    Response.status(404, "gone")
  when "/custom"
    Response.text("made", status: 201, headers: { "x-kit" => "yes" })
  else
    Response.json({
      "request_method" => req.request_method,
      "script_name" => req.script_name,
      "path" => req.path,
      "query" => req.query,
      "probe" => req.headers["x-probe"],
      "body" => req.body
    })
  end
}
