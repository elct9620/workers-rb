App = ->(request) {
  req = Req.new(request)

  case req.path
  when "/text"
    Res.text("plain")
  when "/json"
    Res.json({ "shaped" => true })
  when "/status"
    Res.status(404, "gone")
  when "/custom"
    Res.text("made", status: 201, headers: { "x-kit" => "yes" })
  else
    Res.json({
      "request_method" => req.request_method,
      "script_name" => req.script_name,
      "path" => req.path,
      "query" => req.query,
      "probe" => req.headers["x-probe"],
      "body" => req.body,
      # A second read of a cached field is the same object; a second
      # round-trip to the Host would build a new one.
      "cached" => req.path.equal?(req.path)
    })
  end
}
