# The smallest thing that answers: a Worker is a lambda taking the request as
# a Hash and returning a Rack triplet. Nothing is declared, so nothing beyond
# the request is reachable — and that is already enough to serve.
#
# The two halves of the URL arrive apart: `script_name` is where the Host
# decided this Tenant is mounted, `path` is what is left for the Worker. The
# path form spends a segment on the name, the domain forms spend none, and
# together they read the same either way.

App = ->(env) {
  [200, { "content-type" => "text/plain" }, ["hello from #{env["script_name"]}#{env["path"]}\n"]]
}
