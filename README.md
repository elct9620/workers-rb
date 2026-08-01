# workers-rb

A self-hostable, multi-tenant edge function platform: tenants publish Ruby by
placing files in a shared directory, and the Host serves them from inside
[kobako](https://github.com/elct9620/kobako)'s WASM/mruby sandbox.

> [!WARNING]
> This is a proof of concept, built to demonstrate the idea rather than to
> carry anyone's traffic. There is no tenant authentication, no control-plane
> API, and no quota, billing, or cross-tenant fairness — whoever can write to
> the shared directory is a tenant. Do not run it in production.

[SPEC.md](SPEC.md) is the target state. What runs today is a three-node local
cluster: all three routing forms, per-tenant sandboxes, the Runtime Kit, and
the `Env`, `DB`, `Time`, and `Random` Bindings. The nodes reach one database
server rather than a disk between them, so every node reads and writes every
tenant's database and a write is there for the next request wherever it lands
— and the nodes no longer have to be neighbours to manage it.

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
constant it named, and the Host has one made on first use.

```json
{ "bindings": { "db": { "DB::Main": "main" } } }
```

```ruby
DB::Main.execute("insert into visits values (?)", Time.now)
DB::Main.query("select count(*) as n from visits")   # => [{ "n" => 3 }]
```

Each database is named `<tenant>-<identifier>`, so no Tenant can name
another's, and the Host has one made the first time a tenant reaches for one
that is not there yet. `WORKERS_DB_URL` and `WORKERS_DB_ADMIN_URL` point the
Host at the server holding them — the compose file runs one, and a Host
started outside a container needs one to point at.

### Sizing the database server

Two settings decide how much a cluster can ask of one database server. The
numbers below are this demo's; the way to arrive at yours is what matters,
because a laptop and a cluster do not agree on any of them.

**How much at once.** `WORKERS_DB_POOL` is how many statements one Host has in
flight, and nothing else limits it — a thread that finds every connection busy
waits rather than adding to the pile.

```
pool ≥ the Host's Puma threads          or a thread waits on a connection
                                        rather than on the database
nodes × pool ≤ the server's --max-concurrent-connections   (sqld: 128)
```

**How much disk.** sqld finishes a checkpoint only when no reader is holding
the write-ahead log, and a database under continuous writes never offers that
— so the log grows for as long as the load lasts, whatever the interval is
set to. What the interval decides is how soon a quiet moment is used to
reclaim it.

```
b = write-ahead log bytes per write statement
    run N writes, read dbs/<namespace>/data-wal, divide by N

headroom per database ≈ b × w × D
    w = peak write statements per second
    D = the longest stretch of saturation you expect

SQLD_CHECKPOINT_INTERVAL_S ≤ the shortest quiet gap your traffic has
```

Measured here: `b` ≈ 2 KB, and a log that reached 35 MB under continuous
writes was back to zero within 30 seconds of the writes stopping.

## Testing

```sh
bundle exec rake
```

The suite fetches the binaries it needs — the guest one and a database server
— and drives the real Host in process against both, so what the Binding is
proved against is the server the cluster runs rather than a stand-in. The
server starts on the first test that needs a database and is gone by the time
the run is, whichever way the run ended.

Running a Host outside a container works the same way, once something is
listening where `WORKERS_DB_URL` says:

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
