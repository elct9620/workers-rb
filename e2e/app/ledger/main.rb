# Writes on POST and counts on GET, so a write landing on one Node can be read
# back from whichever Node answers next.
App = ->(env) {
  req = Request.new(env)
  DB::Main.execute("create table if not exists entries (node text, at real)")

  if req.request_method == "POST"
    DB::Main.execute("insert into entries values (?, ?)", Env.node, Time.now)
  end

  Response.json({
    "node" => Env.node,
    "entries" => DB::Main.query("select count(*) as n from entries")[0]["n"]
  })
}
