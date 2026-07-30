# workers-rb

A self-hostable, multi-tenant edge function platform: tenants publish Ruby by
placing files in a shared directory, and the Host serves them from inside
[kobako](https://github.com/elct9620/kobako)'s WASM/mruby sandbox.

[SPEC.md](SPEC.md) is the target state. What runs today is the single-node
development environment: path-form routing, per-tenant sandboxes, and the
`Time` and `Random` Bindings.

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

```ruby
# app/hello/main.rb
App = ->(request) {
  [200, { "content-type" => "text/plain" }, ["hello from #{request.path}\n"]]
}
```

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
network, environment, or process; the request, the clock, and the entropy
source arrive as Host objects that answer only the methods
[SPEC.md](SPEC.md) lists for them.
