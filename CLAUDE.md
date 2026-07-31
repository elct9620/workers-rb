# CLAUDE.md

A prototype platform hosting untrusted Ruby from many tenants in kobako's
WASM/mruby sandbox. [SPEC.md](SPEC.md) is the target state and governs; the
README's opening states what runs today.

## Where decisions live

| Path | Decides |
|------|---------|
| `SPEC.md` | Every observable behavior, keyed `F-*` / `B-*` / `E-*`. When intent moves, it moves here first |
| `lib/workers/host.rb` | How a request finds its Tenant, and which failure becomes which status |
| `lib/workers/registry.rb` | What constitutes a Tenant under the shared directory, and how many the Host keeps |
| `lib/workers/tenant.rb` | When a Sandbox is built, reused, and discarded |
| `lib/workers/guest.rb` | Every Host object tenant code can reach, and the methods it may call on each |
| `lib/workers/environment.rb` | Which request fields cross into the guest |
| `lib/workers/manifest.rb` | What `app.json` may say, and what makes a Tenant unroutable |
| `lib/workers/runtime_kit.rb` | The mruby source every Sandbox carries ahead of tenant files |
| `lib/workers/{node,databases,runtime}.rb` | Host configuration, read from the environment while the class body runs |
| `compose.yaml` + `Caddyfile` | The cluster's shape: how many Nodes, what they share, what stands in front of them |
| `tmp/*.md` | The exploration behind decisions SPEC.md only states. Not in version control |

## What the code does not say

kobako is a sibling project at `../kobako`, not a public gem. Its `SPEC.md`
and `docs/behavior/` are the authoritative account of sandbox semantics and no
web search reaches them — read them rather than inferring.

Ruby under `app/`, `e2e/app/`, and `test/fixtures/app/` is tenant code running
on mruby, not host Ruby. RuboCop excludes it, and its language is whatever the
guest binary carries — the `+full` variant, so JSON and ASCII Regexp, and no
more. `Response.json` takes a Hash positionally, so the braces are not
optional.

A Binding narrows its guest-reachable methods through `respond_to_guest?`, so
a method left off the list is invisible rather than refused. The request is no
Binding: the Host composes it into a Hash, leaving a field it withheld with no
name in the guest at all.

The guest binary is a kobako release asset rather than part of the gem.
`rake wasm:fetch` pins it to the resolved gem version, so the host side and
the guest side cannot drift.

Every test under `test/` drives the real Host through `TestHelper::Case`, which
resets its class-level configuration first. Rack::Test settles its session on a
test's first request, so a shared directory chosen inside `app` is the only one
that test ever reads — `serving` points the Host instead.

`e2e/` loads no Host. It speaks HTTP to a cluster `docker compose` is already
running, and asserts only what no single process could show. `rake` does not
run it; `rake e2e` does.
