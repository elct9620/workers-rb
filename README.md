# workers-rb

A self-hostable, multi-tenant edge function platform: tenants publish Ruby by
placing files in a shared directory, and the Host serves them from inside
[kobako](https://github.com/elct9620/kobako)'s WASM/mruby sandbox.

[SPEC.md](SPEC.md) is the target state. What runs today is a three-node local
cluster: all three routing forms, per-tenant sandboxes, the Runtime Kit, and
the `Env`, `DB`, `Time`, and `Random` Bindings. The nodes share one database
volume, so every node reads and writes every tenant's database and a write is
there for the next request wherever it lands — with none of the lag an
arrangement replicating between nodes would carry.

## Running it

```sh
bundle install
bundle exec rake dev:tenant     # writes a sample tenant into app/
docker compose up -d --wait
curl localhost:9292/hello       # WORKERS_PORT moves this off 9292
```

Three Hosts sit behind one address, taking requests in turn, so consecutive
calls report a different `Env.node`.

Tenant code lives in `app/<tenant>/` — an `app.json` Manifest and one or more
`*.rb` files, loaded in filename order. The directory is mounted into every
node, so adding or editing a tenant reaches the next request without a restart
and without visiting each one.

A tenant answers at `/<tenant>`, at `<tenant>.<base>` once `WORKERS_BASE_DOMAIN`
names the base, and at whatever `domain` its Manifest declares. The domain forms
leave the whole path to the Worker; only the path form spends a segment naming
the tenant.

```ruby
# app/hello/main.rb
App = ->(env) {
  [200, { "content-type" => "text/plain" }, ["hello from #{env["path"]}\n"]]
}
```

A Tenant that declares a database in its Manifest reaches it under the
constant it named, and the Host creates the file on first use.

```json
{ "bindings": { "db": { "DB::Main": "main" } } }
```

```ruby
DB::Main.execute("insert into visits values (?)", Time.now)
DB::Main.query("select count(*) as n from visits")   # => [{ "n" => 3 }]
```

Each database is named `<tenant>-<identifier>`, so no Tenant can name
another's. `WORKERS_DB_DIR` points the Host at where they live — a directory
of `.db` files today; `rake dev:tenant` creates `db/` for running outside a
container.

## Testing

```sh
bundle exec rake
```

The suite fetches the guest binary it needs and drives the real Host in
process. Running one outside a container works the same way:

```sh
bundle exec puma
```

What one process cannot show — that every node serves the same tenants, that
a write from any of them reaches the rest, that one address reaches them all
— is checked against the running cluster instead:

```sh
docker compose up -d --wait
bundle exec rake e2e
```

It publishes the tenants under `e2e/app/` into the shared directory and then
speaks only HTTP, naming no node.

## What tenant code can reach

Nothing but what the Host hands it. The mruby guest has no filesystem,
network, environment, or process. A Worker receives the request as a plain
Hash the Host composed, so a field the Host left out has no name to call at
all; the node it runs on, the databases it declared, the clock, and the
entropy source arrive as Host
objects that answer only the methods [SPEC.md](SPEC.md) lists for them.

Every sandbox also carries the Runtime Kit — `Request` to read that Hash by
name, and `Response` to shape a Rack triplet as text, as JSON, or with a
chosen status. It runs inside the guest and grants nothing; a Worker that
returns a triplet itself needs none of it.

```ruby
App = ->(env) {
  req = Request.new(env)
  Response.json({ "node" => Env.node, "path" => req.path })
}
```
