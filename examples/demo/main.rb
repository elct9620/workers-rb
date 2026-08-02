# The landing page of the cluster: every refresh writes a visit and reads the
# whole tally back, so what the page shows is the one thing a single Host
# cannot demonstrate — the node that answered changes, and the count does not
# care which one it was.
#
# `/demo/json` is the same facts without the page, for anything reading rather
# than looking.

def escape(text)
  text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end

def facts
  DB::Main.execute("create table if not exists visits (node text, at real)")
  DB::Main.execute("insert into visits values (?, ?)", Env.node, Time.now)

  {
    "tenant" => Env.tenant,
    "node" => Env.node,
    "request_id" => Env.request_id,
    "at" => Time.now,
    "visits" => DB::Main.query("select count(*) as n from visits")[0]["n"],
    "by_node" => DB::Main.query(
      "select node, count(*) as n from visits group by node order by n desc"
    )
  }
end

def page(data)
  rows = data["by_node"].map { |row|
    "<tr><td>#{escape(row["node"])}</td><td>#{row["n"]}</td></tr>"
  }.join("\n")

  <<~HTML
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>workers-rb</title>
    <style>
      body { font-family: ui-monospace, monospace; max-width: 40rem;
             margin: 4rem auto; padding: 0 1.5rem; line-height: 1.6;
             color: #1a1a1a; background: #fafafa; }
      h1 { font-size: 1.4rem; margin-bottom: 0; }
      p.lede { color: #666; margin-top: .3rem; }
      dl { display: grid; grid-template-columns: max-content 1fr; gap: .3rem 1.5rem; }
      dt { color: #666; }
      table { border-collapse: collapse; margin-top: .5rem; width: 100%; }
      th, td { text-align: left; padding: .3rem .6rem; border-bottom: 1px solid #ddd; }
      footer { margin-top: 2.5rem; color: #888; font-size: .85rem; }
    </style>
    </head>
    <body>
    <h1>#{escape(data["tenant"])}</h1>
    <p class="lede">Ruby in a WASM sandbox, answered by whichever Host took the request.</p>

    <dl>
      <dt>node</dt><dd>#{escape(data["node"])}</dd>
      <dt>request</dt><dd>#{escape(data["request_id"])}</dd>
      <dt>visits</dt><dd>#{data["visits"]}</dd>
    </dl>

    <p>Every Host writes into the same database, so this tally is the cluster's
    rather than this Host's. Refresh — the node changes, the count carries on.</p>

    <table>
      <tr><th>node</th><th>visits</th></tr>
      #{rows}
    </table>

    <footer>The same facts as JSON: <a href="/demo/json">/demo/json</a></footer>
    </body>
    </html>
  HTML
end

App = ->(env) {
  req = Request.new(env)
  data = facts

  if req.path == "/json"
    Response.json(data)
  else
    Response.text(page(data), headers: { "content-type" => "text/html; charset=utf-8" })
  end
}
