# workers-rb

A self-hostable, multi-tenant edge function platform: tenants publish Ruby by
placing files in a shared directory, and the Host serves them from inside
[kobako](https://github.com/elct9620/kobako)'s WASM/mruby sandbox.

> [!WARNING]
> This is a proof of concept, built to demonstrate the idea rather than to
> carry anyone's traffic. There is no tenant authentication, no control-plane
> API, and no quota, billing, or cross-tenant fairness — whoever can write to
> the shared directory is a tenant. Do not run it in production.

[SPEC.md](SPEC.md) is the target state. What runs today is a multi-node
cluster — locally under `docker compose`, or on Kubernetes through
`charts/workers`: all three routing forms, per-tenant sandboxes, the Runtime
Kit, and the `Env`, `DB`, `Time`, and `Random` Bindings. The nodes name one database
server between them, so every node reads and writes every tenant's database
and a write is there for the next request wherever it lands.

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

## Deploying to a cluster

`charts/workers` asks Kubernetes for the same shape: several Hosts reading one
shared directory, one database server they all name, and one internal address.

```sh
helm install workers oci://ghcr.io/elct9620/workers-rb/workers \
  --version 0.1.0 \
  --set sharedDirectory.existingClaim=tenants
```

Each release publishes the chart beside the Host image it installs, under one
version, so the two never disagree about what is running. `--version` is what
pins a cluster to one; without it Helm takes whatever is newest, which is not
the same answer next month.

No release has been cut yet, so there is nothing published to install. Until
there is, the chart installs from a clone and has to be told which Host to
run, because the one it would otherwise name has not been built:

```sh
helm install workers charts/workers \
  --set image.tag=main \
  --set sharedDirectory.existingClaim=tenants
```

The shared directory is named rather than created, and has no default. Every
Node has to read the same one — a volume only one Host can mount produces a
cluster that disagrees about which Tenants exist without any Host reporting an
error — so the install stops until a claim is named. The chart creates none,
because how the volume is backed is also how Tenants get written into it, and
a claim made here would arrive with no way to publish through: the Hosts mount
it read-only, and something outside this release does the writing.

The chart installs no Gateway. It creates the internal Service and prints the
address to point a tunnel, reverse proxy, or load balancer at. Which Node
answers a request follows that Gateway's connection handling — one that keeps
a connection open reaches one Host for its lifetime. `Env.node` reports the
Pod's name, which changes when the Hosts are rolled.

Each Host answers `/_health/live` and `/_health/ready` for whatever runs it:
the first says the process is up, the second that this Host reads the shared
directory, which is what a Pod that should be passed over gets wrong on its
own. Both are the Host's on every hostname, so a Gateway pointed at the
Service carries them on every Tenant's domain — turning them away there is
the operator's to do.

The database server is one Pod holding one volume, so `databases.storageClass`
decides what a lost machine costs: a class whose volume follows the Pod has the
server rescheduled, one bound to a machine has it waited for. NFS serves the
shared directory well and a database badly — SQLite's locking is the
difference.

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

## What a failure costs

One set of limits holds every tenant to the same bound; a Manifest does not
move them.

| Limit | Value | What the caller gets |
|-------|-------|----------------------|
| Wall clock per invocation | 5 seconds | 503, marked as a timeout |
| Memory per invocation | 16 MiB | 503, marked as a memory limit |
| Request body | 512 KiB | 413, before any Worker runs |

Each Host holds the body limit itself, so a node reached directly is still a
node that refuses an oversized body — and refuses it before reading it.
Whatever stands in front of the cluster may refuse it earlier: the local
cluster's proxy does, and a Gateway you supply is yours to say.

A failure is one request's outcome. Tenant code that raises, loops forever, or
returns something that is not a Rack triplet ends that request 5xx carrying
its failure class, and beyond that nothing from outside the sandbox — no Host
path, no environment, no internal address. The other tenants keep answering
and the Host process keeps running. A failure that leaves the sandbox unusable
has it discarded, and that tenant's next request builds a new one.

Since nothing a Worker writes reaches the response, whatever it puts on
standard output or error lands in the log of the node that ran it, named by
the tenant it came from — which is the only thing a tenant author has to debug
with:

```sh
docker compose logs node-a    # hello out: about to query
```
