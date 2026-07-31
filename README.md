# workers-rb

A self-hostable, multi-tenant edge function platform: tenants publish Ruby by
placing files in a shared directory, and the Host serves them from inside
[kobako](https://github.com/elct9620/kobako)'s WASM/mruby sandbox.

[SPEC.md](SPEC.md) is the target state. What runs today is the single-node
development environment: all three routing forms, per-tenant sandboxes, the
Runtime Kit, and the `Env`, `DB`, `Time`, and `Random` Bindings. A write
reaches the local database file whatever `WORKERS_WRITER` says, because
routing a replica's writes to the Writer arrives with the cluster.

## Running it

```sh
bundle install
bundle exec rake dev:tenant     # writes a sample tenant into app/
docker compose up -d --wait
curl localhost:9292/hello
```

Tenant code lives in `app/<tenant>/` — an `app.json` Manifest and one or more
`*.rb` files, loaded in filename order. The directory is mounted into the
container, so adding or editing a tenant reaches the next request without a
restart.

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

The files sit flat on the database mount as `<tenant>-<identifier>.db`, so
no Tenant can name another's. `WORKERS_DB_DIR` points the Host at that mount;
`rake dev:tenant` creates `db/` for running outside a container.

## Testing

```sh
bundle exec rake
```

The suite fetches the guest binary it needs. Running the Host outside a
container works the same way:

```sh
bundle exec puma
```

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
