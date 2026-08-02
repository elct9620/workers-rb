# workers-rb

A self-hostable, multi-tenant edge function platform. Tenants publish Ruby by
placing files in a shared directory, and the Host serves them from inside
[kobako](https://github.com/elct9620/kobako)'s WASM/mruby sandbox — no
filesystem, no network, and nothing of the Host but the Bindings it hands in.

> [!WARNING]
> A proof of concept: it demonstrates the idea rather than carrying anyone's
> traffic. Run it on a cluster, but not one serving production.

## Try it

```sh
bundle install
bundle exec rake dev:publish    # copies examples/ into app/
docker compose up -d --wait
curl localhost:9292/hello       # WORKERS_PORT moves this off 9292
```

Three Hosts sit behind one address. Call it twice and `Env.node` differs.

## Publish a Worker

A Tenant is one directory under `app/`. Its directory name is its name, and an
`app.json` Manifest is what makes it routable. The Worker is the constant your
`*.rb` files define — `App`, unless the Manifest names another.

```ruby
# app/hello/main.rb
App = ->(env) {
  [200, { "content-type" => "text/plain" }, ["hello from #{env["script_name"]}#{env["path"]}\n"]]
}
```

`app/` is mounted into every Node, so adding or editing a Tenant reaches the
next request without a restart and without visiting each one.

A Tenant answers at three addresses. For a request ending in `/x`:

| Form | Address | `script_name` | `path` |
|------|---------|---------------|--------|
| Custom domain | `<the domain its app.json declares>/x` | `""` | `/x` |
| Subdomain | `hello.<WORKERS_BASE_DOMAIN>/x` | `""` | `/x` |
| Path | `/hello/x` | `/hello` | `/x` |

Matched top to bottom. Only the path form spends a segment naming the Tenant.

## Databases

A Tenant declares a database in its Manifest and reaches it under the constant
it named. The Host has one made on first use.

```json
{ "bindings": { "db": { "DB::Main": "visits" } } }
```

```ruby
DB::Main.execute("insert into visits values (?)", Time.now)
DB::Main.query("select count(*) as n from visits")   # => [{ "n" => 3 }]
```

Each database is named `<tenant>-<identifier>`, so no Tenant can name
another's. `WORKERS_DB_URL` and `WORKERS_DB_ADMIN_URL` point the Host at the
server holding them, and `docker compose` runs one.

## Deploy it

<!-- x-release-please-start-version -->
```sh
helm install workers-rb oci://ghcr.io/elct9620/workers-rb \
  --version 0.4.0 \
  --set sharedDirectory.existingClaim=tenants
```
<!-- x-release-please-end -->

Several Hosts read one shared claim, one database server they all name, and
one internal Service to point a Gateway at. You supply the claim: the Hosts
mount it read-only, so publishing into it happens outside the release.
[`charts/workers-rb`](charts/workers-rb) has the rest.

## What runs today

All three routing forms, a Sandbox per Tenant, the Runtime Kit, and the `Env`,
`DB`, `Time`, and `Random` Bindings. The Nodes name one database server
between them, so a write is there for the next request wherever it lands.
[SPEC.md](SPEC.md) is the target state.

## Where to look next

| Path | What it holds |
|------|---------------|
| [SPEC.md](SPEC.md) | Every behavior, keyed `F-*` / `B-*` / `E-*` — what a Worker may reach, and what a failure costs |
| [`examples/`](examples) | Tenants that run, written to be read |
| [`charts/workers-rb`](charts/workers-rb) | Every value the chart takes, and how to size the database server |
| [`compose.yaml`](compose.yaml) | The local cluster's shape |

## Development

```sh
bundle exec rake        # the suite, against a real Host and a real database server
bundle exec rake e2e    # against the cluster, once `docker compose up -d --wait` has it
bundle exec puma        # one Host outside a container
```

Nothing a Worker prints reaches the response. It lands in the log of the Node
that ran it, named by the Tenant it came from, which is what a Tenant author
debugs with:

```sh
docker compose logs node-a    # hello out: about to query
```
