App = ->(env) {
  puts "worked on #{env["path"]}"
  $stderr.puts "and had something to say about it"

  raise "gave up" if env["path"] == "/fail"

  [200, { "content-type" => "text/plain" }, ["done"]]
}
