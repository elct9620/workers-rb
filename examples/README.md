# Examples

Tenant code, written to be read. Each directory is one Tenant — an `app.json`
Manifest and the `*.rb` files the Host loads in filename order — and copying
one into the shared directory is all publishing is.

| Example | Shows |
|---------|-------|
| [`hello`](hello) | The smallest Worker that answers, declaring nothing |
| [`demo`](demo) | Routing, the `Env` and `DB` Bindings, and one database every Host shares |

```sh
bundle exec rake dev:publish     # copies them all into app/
docker compose up -d --wait
curl localhost:9292/hello
```

This is mruby inside the sandbox, not the Host's Ruby: the language is
whatever the guest binary carries — JSON and ASCII Regexp, and no more — and
there is no filesystem, network, or process to reach. Everything a Worker can
touch arrives from the Host, and [SPEC.md](../SPEC.md) lists the methods each
of those objects answers.
