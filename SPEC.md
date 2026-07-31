# SPEC.md — workers-rb

## Intent

### Purpose

workers-rb builds a self-hostable, multi-tenant edge function platform on kobako's WASM/mruby sandbox, demonstrating that the Ruby ecosystem can safely host untrusted Ruby code on a shared cluster and serve HTTP requests from it — a position currently occupied only by JavaScript-ecosystem services.

### Users

| User | Goal |
|------|------|
| Platform operator | Deploy and run the cluster, publish a tenant by placing files, and observe which node served which request |
| Tenant author | Obtain a publicly reachable HTTP endpoint by placing `app.json` and `*.rb` in a shared directory — no packaging, image build, or deploy pipeline |
| Technology evaluator | Judge whether Ruby can carry multi-tenant hosting of untrusted code, and see exactly where the isolation boundary lies and what it costs |

### Impacts

| Impact | Observable behavior |
|--------|---------------------|
| Publish by placing files | After a tenant author adds `/app/<tenant>/` to the shared directory, that tenant's endpoint serves requests without a Host restart or redeploy |
| Sandbox isolation | Tenant code cannot read the Host's environment variables, filesystem, or network; the Bindings the Host supplies are its only path outward |
| Data binding | A tenant declares multiple SQLite Bindings in its Manifest and reads and writes them through named constants whatever Node serves the request, and cannot reach another tenant's databases |
| Node visibility | The same request to the same tenant reads a different `Env.node` on different nodes, while its Binding reads converge on identical results |
| Failure containment | An exception, timeout, or memory exhaustion in tenant code affects only that request; the Host process and other tenants' requests are unaffected |
| Rack compatibility | Tenant code returns a Rack response triplet, which the Host hands to the HTTP layer without semantic translation |

### Success Criteria

| Criterion | Verification |
|-----------|--------------|
| Publishing needs no restart | Adding a tenant directory to a running Host makes `GET https://<domain>/<tenant>` respond 200 |
| The sandbox is closed | Tenant code's attempts to reach environment variables, the filesystem, and the network all fail, and the failures disclose no Host environment content |
| Tenants are isolated from each other | Tenant A's code cannot obtain any Binding declared by tenant B |
| Cross-node results converge | Across consecutive requests served by different nodes, `Env.node` differs while queries against the same Binding converge on the same result |
| Writes work from every node | A request served by any node writes to its Binding successfully, and the write is visible to subsequent requests on the node that served it |
| Failures do not spread | While tenant code loops forever, that request ends 5xx and other tenants' requests keep responding normally |

### Non-Goals

- Billing, quotas, SLA management, and cross-tenant fairness scheduling
- A control-plane API and tenant authentication — the shared directory is the only deployment interface
- Bindings other than SQLite (KV, object storage, queues, durable objects)
- Schema definition and migration for tenant databases — tenant code creates its own tables
- Strongly consistent reads across Nodes — a write reaches the Nodes that did not serve it in time rather than at once
- An online editor, version management, or rollback for tenant code
- Tenant runtimes other than mruby
- Reimplementing or wrapping kobako's sandbox semantics — kobako provides the isolation guarantees

### Core Abstractions

These roles constitute the system. Later layers use these names exclusively.

| Role | Responsibility | Scope |
|------|---------------|-------|
| **Host** | The Ruby process running on each Node: accepts HTTP requests, resolves routes, loads tenants, supplies Bindings, and obtains responses | In scope |
| **Tenant** | One application unit under the shared directory (`/app/<tenant>/`), consisting of a Manifest and mruby source | In scope |
| **Manifest** | `/app/<tenant>/app.json` — declares the tenant's entrypoint, external domain form, and Bindings | In scope |
| **Worker** | The entrypoint constant defined by a Tenant's mruby source; accepts the request environment and returns a Rack response triplet | In scope |
| **Binding** | A named Host object supplied into the Sandbox — `Env`, `DB`, `Time`, or `Random` — and tenant code's only path outward | In scope |
| **Runtime Kit** | mruby helper objects the Host loads into every Sandbox, present regardless of Tenant files | In scope |
| **Node** | A cluster node running one Host instance; every Node reads and writes every Tenant's databases | In scope |
| **Sandbox** | kobako's mruby execution unit; the Host holds one per Tenant and serves requests through successive invocations | kobako semantics, referenced |
| **kobako** | The gem providing the WASM/mruby sandbox, Service injection, and error classification | Out of scope — referenced, not designed |

---

## Scope

### System Boundary

#### Responsibility — what the Host does / does not do

**Does:**

- Discover Tenants under the shared directory, and read and validate their Manifests
- Resolve a request to exactly one Tenant by either path form or Host header form
- Hold, per Tenant, a Sandbox loaded with the Runtime Kit and that Tenant's source, and rebuild it after its files change
- Supply `Env` and each `DB` Binding declared in the Manifest for the duration of one invocation
- Create a declared Binding's database file when it does not exist, and open it for the invocation
- Supply the `Time` and `Random` Bindings, which read the Host's clock and entropy
- Compose the request environment from the request and pass it as the Worker's only argument, then hand the returned triplet to the HTTP layer
- Narrow every Binding's guest-reachable method surface to an explicit allow list
- Turn a Tenant's execution failure into an HTTP error response for that request

**Does not:**

- Provide tenant authentication, authorization, or a tenant self-service interface
- Provide routing, templating, an ORM, or an HTTP client to tenant code
- Define, create, or migrate a Tenant's database tables
- Cache or rewrite the content of a tenant's HTTP response
- Retain tenant execution state across requests

#### Interaction — input assumptions / output guarantees

**Input assumptions:**

- The shared directory sits on a filesystem every Node mounts; a change made through any Node's mount becomes visible through every other Node's mount. Tenant directories are added and modified by processes outside the Host
- Every Node reaches every Tenant's SQLite databases for both reading and writing, and a write reaches the Nodes that did not serve it in time
- External traffic reaches an internal cluster service through a tunnel service; the Host is not exposed to the public network directly

**Output guarantees:**

- Every request yields exactly one HTTP response; tenant code terminates the Host process under no outcome
- `Env.node` reflects the Node that actually executed that invocation
- Tenant code obtains the Host's environment variables, filesystem paths, and network connections under no circumstance
- Tenant code reads exactly what the Host placed in the request environment, and reaches nothing the Host left out of it

#### Control — what the Host controls / depends on

- **Controls:** route resolution, Sandbox lifecycle, the content and method surface of each Binding, the creation of each Binding's database, and the mapping from failure to HTTP status
- **Depends on:** kobako's isolation and error classification, the Sandbox's mruby build providing JSON generation and ASCII Regexp, the storage backing the Tenants' databases being reachable for reading and writing from every Node, the readability of shared storage, the hostname the operating system reports for this Node, and the tunnel service's external connectivity

### Feature List

| ID | Feature |
|----|---------|
| F-01 | Tenant discovery and Manifest loading |
| F-02 | Request routing (path form and host form) |
| F-03 | Sandbox caching and lifecycle |
| F-04 | Env Binding |
| F-05 | DB Binding |
| F-06 | Runtime Kit |
| F-07 | Failure containment and response mapping |
| F-08 | Deployment topology |

### User Journeys

#### J-01 — A tenant author publishes a Worker

- **Context:** The shared directory is writable and a Host runs on every Node
- **Action:** Create `/app/hello/` holding an `app.json` that declares the domain form and a `main.rb` that defines the entrypoint constant
- **Outcome:** `GET https://<domain>/hello` returns what the Worker produced, with no Host restarted

#### J-02 — A tenant author uses a SQLite Binding

- **Context:** The Tenant is live
- **Action:** Declare a Binding in the Manifest, then query and write it from tenant code
- **Outcome:** The query returns rows and the write is visible to later requests on the node that served it; the code cannot reach a Binding declared by another Tenant

#### J-03 — A technology evaluator compares cross-node behavior

- **Context:** The cluster has several Nodes and one Tenant is live
- **Action:** Issue consecutive requests to one endpoint and compare `Env.node` against the Binding query results
- **Outcome:** `Env.node` tracks the serving Node, queries against the same Binding converge on the same result, and writes succeed from any Node

#### J-04 — A platform operator deploys the cluster

- **Context:** A multi-node cluster is available, with a shared filesystem for the tenant directory and storage every Node reaches for the databases
- **Action:** Deploy the Host workload, mount the shared directory, point each Host at the database storage, and point the tunnel at the internal service
- **Outcome:** Requests to the external domain reach a Host on any Node and are answered, and a write succeeds whichever Node serves it

#### J-05 — Tenant code fails

- **Context:** One Tenant's code contains an infinite loop
- **Action:** Request that Tenant's endpoint and another Tenant's endpoint concurrently
- **Outcome:** The former ends 5xx with a failure class once the timeout elapses, the latter responds normally, and the Host process keeps running

---

## Behavior

### F-01 — Tenant discovery and Manifest loading

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-01 | `/app/<tenant>/app.json` exists and is a valid Manifest + the Host reads it | The Tenant becomes routable, and its entrypoint, domain form, and Binding declarations take effect |
| B-02 | A directory holds no `app.json`, or its name does not satisfy the Tenant name rule | The directory constitutes no Tenant and is not routable |
| B-03 | A Tenant directory holds several `*.rb` files | All are loaded into one Sandbox in lexicographic filename order, so a later file may reference constants an earlier one defined |
| B-04 | A Tenant directory is added, changed, or removed while the Host runs | Each request resolves against the shared directory's current content: an added Tenant is routable, changed content serves the next request reaching that Tenant, and a removed Tenant stops being routable and has its Sandbox discarded |

### F-02 — Request routing

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-05 | The request path's first segment equals the Tenant name | Routes to that Tenant; the Worker receives that segment as `script_name` and the remainder as `path`, split per Rack's SCRIPT_NAME / PATH_INFO convention |
| B-06 | The Manifest declares a domain + the request's Host header matches it | Routes to that Tenant; `script_name` is empty and `path` is the full request path |
| B-07 | The Host's base domain is configured + the request's Host header is `<tenant>.<base>` | Routes to that Tenant; `script_name` is empty and `path` is the full request path |
| B-08 | A request matches more than one form | Forms are matched in order: the Manifest `domain`, then `<tenant>.<base>`, then the path form |

### F-03 — Sandbox caching and lifecycle

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-09 | A Tenant is routed to for the first time | The Host creates a Sandbox, loads the Runtime Kit and that Tenant's `*.rb`, declares `Env`, `Time`, `Random`, and each Manifest Binding as pending, then dispatches the entrypoint |
| B-10 | The Tenant has a Sandbox and its files are unchanged | That Sandbox serves the dispatch; source is not reloaded |
| B-11 | The Tenant's files have changed | The Tenant's Sandbox is discarded and rebuilt per B-09, then dispatched |
| B-12 | Concurrent requests to one Tenant | They share that Tenant's Sandbox; each invocation holds its own Bindings, output captures, and resource usage |
| B-13 | Any invocation ends | That invocation's supplied Bindings and output captures end with it and do not carry into the next |
| B-14 | Tenant code reads the clock or draws a random number | The `Time` and `Random` Bindings supply them from the Host's clock and entropy; environment variables, filesystem paths, and network connections stay unreachable |

### F-04 — Env Binding

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-15 | Every invocation | The Host supplies `Env`, whose surface exposes the executing Node's hostname, the Tenant name, and the request identity |
| B-16 | Tenant code calls a method on a Binding outside the allow list | The call raises inside the Sandbox and tenant code may rescue it; left unrescued it ends the request per E-10. The refusal names no Host environment content |
| B-17 | Requests to one Tenant are served by different Nodes | Each invocation's `Env.node` reflects the Node that executed it |

### F-05 — DB Binding

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-18 | The Manifest declares a Binding + every invocation | The Host supplies the corresponding SQLite Binding under the declared constant name |
| B-19 | A declared Binding's database does not exist + the Binding is supplied | The Host creates it, then supplies it |
| B-20 | Tenant code queries a Binding | Returns an Array of rows, each a Hash of column name to value |
| B-21 | Tenant code writes to a Binding | The write completes and returns the affected row count, whichever Node serves the request |
| B-22 | A later request queries the same Binding after a write | The query reflects that write immediately on the Node that served the write, and on every other Node in time; until then those Nodes read the previous value |
| B-23 | A statement a Tenant executes against a Binding fails in the database | The failure reaches tenant code as an exception it may rescue |
| B-24 | A Binding constant the Manifest does not declare | The constant does not exist in the Sandbox and referencing it raises `NameError`, which tenant code may rescue and which stays distinguishable from a declared Binding that is not yet supplied |
| B-25 | A Tenant's Binding constant | Resolves only to a database that Tenant declared |

### F-06 — Runtime Kit

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-26 | Every Sandbox | The Runtime Kit loads before the Tenant's `*.rb`, so tenant code may use its constants at the top level |
| B-27 | Tenant code uses the Runtime Kit | It reads the request environment through named fields and builds a Rack response triplet as plain text, as JSON, or with a chosen status code |
| B-28 | Tenant code returns a triplet directly without the Runtime Kit | Equally valid; the Host's handling is unchanged |
| B-29 | A Tenant's `*.rb` defines a constant that the Runtime Kit or a Binding also defines | The Tenant's definition takes effect, and that Tenant's code no longer reaches what the name held before |

### F-07 — Failure containment and response mapping

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-30 | The Worker returns a valid Rack response triplet | The Host hands it to the HTTP layer unchanged |
| B-31 | Any failure in any Tenant | Other Tenants' requests are unaffected and the Host process keeps running |
| B-32 | A trap-class failure | The Tenant's Sandbox is discarded and the next request rebuilds it per B-09, and that Tenant's other in-flight invocations end with the same failure class |
| B-33 | Any failure response | Carries no Host environment variable, filesystem path, or internal address; a failure in tenant execution additionally carries its failure class |

### F-08 — Deployment topology

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-34 | The Host workload runs on several Nodes + the shared directory is mounted on each | Every Node sees the same set of Tenants |
| B-35 | The Host workload runs on several Nodes + a Tenant declares a Binding | Every Node reads and writes that Tenant's database |
| B-36 | The tunnel service points at the internal service | Requests to the external domain reach a Host on any Node |

### Error Scenarios

| ID | Trigger | Response |
|----|---------|----------|
| E-01 | Neither the Host header nor the path's first segment matches a Tenant | 404 |
| E-02 | A Manifest is not a JSON object, or a field violates its declared shape or naming rule | The Tenant is not routable and its endpoints answer 404; the Host records the Tenant as invalid |
| E-03 | Two Tenants declare the same domain | Neither is routable and both endpoints answer 404 |
| E-04 | A Tenant's `*.rb` fails to compile | 500 marked as a compile failure |
| E-05 | No `*.rb` defines the entrypoint constant the Manifest names | 500 marked as an undefined entrypoint, listing the top-level constants the Sandbox defines |
| E-06 | Tenant code raises an exception it does not rescue | 500 marked as a tenant exception |
| E-07 | The Worker's return value is not a valid Rack response triplet | 500 marked as an invalid response |
| E-08 | Tenant code exceeds the timeout | 503 marked as a timeout |
| E-09 | Tenant code exhausts the memory limit | 503 marked as a memory limit |
| E-10 | Tenant code leaves a refused Binding call unrescued — a method outside the allow list, or a pending Binding called before it is supplied | 500 marked as a binding failure |
| E-11 | A Binding's database cannot be created or opened | 500 marked as a binding failure; the Host records what it could not reach |
| E-12 | A write to a Binding cannot be completed | 500 marked as a binding failure; the Host records what it could not reach |
| E-13 | The shared directory is unreadable | Every Tenant endpoint answers 503; a cached Sandbox does not serve while the directory is unreadable; the Host records what it could not read |
| E-14 | The Sandbox produces no recognisable result and its execution environment is corrupted | 503 marked as runtime corruption |

---

## Refinement

### Terminology

| Term | Meaning |
|------|---------|
| **Host** | The workers-rb process running on one Node. "Host" always names this process, never HTTP's Host header, which is written "Host header" throughout |
| **Tenant** | One application unit under the shared directory, identified by its directory name |
| **Manifest** | `/app/<tenant>/app.json` |
| **Worker** | The callable that the entrypoint constant named by the Manifest refers to |
| **request environment** | The Hash the Host composes from one request and passes as the Worker's only argument. Tenant code names it `env`; `Env`, capitalised, always names the Binding and never this Hash |
| **Binding** | A named Host object supplied into a Sandbox. `Env` carries node and request information; `DB::*` carries a SQLite database; `Time` carries the Host's clock; `Random` carries the Host's entropy |
| **Runtime Kit** | The mruby helper objects the Host loads into every Sandbox |
| **Node** | A cluster node running one Host |
| **invocation** | One entrypoint call the Host makes into a Sandbox, corresponding to exactly one HTTP request |
| **failure class** | The category a failure response carries: compile failure, undefined entrypoint, tenant exception, invalid response, timeout, memory limit, binding failure, or runtime corruption |
| **trap-class failure** | A failure that leaves the Sandbox unusable: the timeout, the memory limit, or runtime corruption |
| **supply** | The Host's act of providing a Binding object for the span of one invocation. A pending Binding that is called before it is supplied raises per B-16 |

### Contracts

#### Host configuration

The operator supplies these to each Host as environment variables. They are cluster-level; a Manifest does not alter them.

| Setting | Meaning |
|---------|---------|
| Base domain | The suffix under which `<tenant>.<base>` resolves per B-07 |
| Shared directory | The mount path holding `/app/<tenant>/` |
| Database location | Where this Host reaches the Tenants' databases |

#### Manifest

Every field is optional; an empty object is a valid Manifest. `bindings` appears only when the Tenant needs a database. A Manifest carrying a field that violates the shape below, or a name that violates the naming rules, is invalid per E-02.

| Field | Required | Meaning |
|-------|----------|---------|
| `entrypoint` | No | The Worker's entrypoint constant name; `App` when omitted |
| `domain` | No | A custom full domain for this Tenant, binding per B-06. `<tenant>.<base>` and the path form reach the Tenant regardless of this field |
| `bindings.db` | No | SQLite Binding declarations, mapping a constant name to a database identifier |

```json
{
  "entrypoint": "App",
  "domain": "example.com",
  "bindings": {
    "db": { "DB::Main": "main", "DB::Logs": "logs" }
  }
}
```

#### Names

| Name | Legal characters | Length |
|------|------------------|--------|
| Tenant name — the directory name | `a`–`z`, `0`–`9`, `-`; neither leading nor trailing `-` | 1–63 |
| Database identifier | `a`–`z`, `0`–`9`, `_` | 1–32 |
| Manifest Binding constant name | `DB::` followed by an uppercase letter and further letters, digits, or `_` | 1–64 after `DB::` |

A Manifest-declared Binding constant lives under `DB::`, so a Manifest declaration reaches no constant the Runtime Kit or the Tenant defines at the top level.

#### Worker entrypoint

The entrypoint constant is a callable accepting the request environment and returning a Rack response triplet.

```ruby
App = ->(env) {
  [200, { "content-type" => "text/plain" }, ["hello from #{Env.node}\n"]]
}
```

| Position | Shape |
|----------|-------|
| Argument | The request environment |
| Returned `status` | Integer |
| Returned `headers` | Hash of String keys to String values |
| Returned `body` | Array of String |

#### Request environment

The Host composes one Hash per invocation and passes it whole. It carries these keys and no others, so a field the Host left out is not reachable by any name tenant code can spell.

| Key | Value |
|-----|-------|
| `request_method` | The HTTP method as a String |
| `script_name` | The path prefix that routed to this Tenant, as a String |
| `path` | The remainder of the request path, as a String |
| `query` | A Hash of query parameters |
| `headers` | A Hash of request headers, each name lowercased and appearing once, carrying the value the HTTP layer resolved for it |
| `body` | The request body as a String |

The environment is a value the Sandbox holds, not a Binding it dispatches to, so B-16's allow list does not apply to it and no read of it is refused. The request body is part of it and counts against the invocation's memory limit: a body the limit cannot hold ends the request per E-09 whatever the Worker does with it.

#### Guest-reachable method surface

Calls to methods outside these tables are refused per B-16.

| Binding | Method | Returns |
|---------|--------|---------|
| `Env` | `node` | The executing Node's hostname, as a String |
| `Env` | `tenant` | The Tenant name, as a String |
| `Env` | `request_id` | This request's identity as a String, distinct from that of every other request the Host serves |
| `DB::*` | `query(sql, *params)` | An Array of rows, each a Hash of column name to value |
| `DB::*` | `execute(sql, *params)` | The affected row count |
| `Time` | `now` | The current Unix time in seconds, as a Float |
| `Random` | `rand(limit = nil)` | An Integer in `0...limit`, or a Float in `0.0...1.0` when `limit` is omitted |

A row's values reach tenant code as Integer, Float, String, or nil.

#### Request path splitting

`script_name` and `path` divide the request path per Rack's SCRIPT_NAME / PATH_INFO convention, so at most one of them is empty.

| Routing form | Request path | `script_name` | `path` |
|--------------|--------------|---------------|--------|
| Path form on Tenant `hello` | `/hello` | `/hello` | `""` |
| Path form on Tenant `hello` | `/hello/` | `/hello` | `/` |
| Path form on Tenant `hello` | `/hello/items` | `/hello` | `/items` |
| Host form | `/items` | `""` | `/items` |

#### Runtime Kit

The Runtime Kit defines `Request` and `Response`, and nothing else.

| Constant | Call | Result |
|----------|------|--------|
| `Request` | `.new(env)` | Reads the request environment the Worker received |
| `Request` | `#request_method` `#script_name` `#path` `#query` `#headers` `#body` | The value the environment carries under the key of that name |
| `Response` | `.text(body, status:, headers:)` | A Rack triplet with `content-type: text/plain; charset=utf-8` |
| `Response` | `.json(data, status:, headers:)` | A Rack triplet with `content-type: application/json`, its body the JSON form of `data` |
| `Response` | `.status(code, body)` | A Rack triplet with `content-type: text/plain; charset=utf-8` |

```ruby
App = ->(env) {
  req = Request.new(env)
  Response.json({ "node" => Env.node, "path" => req.path })
}
```

#### Execution limits

One set of limits applies to every Tenant; a Manifest does not alter them.

| Limit | Value | On exhaustion |
|-------|-------|---------------|
| Wall clock per invocation | 5 seconds | E-08 |
| Memory per invocation | 16 MiB | E-09 |
| Captured output per invocation | 64 KiB each for the standard output and error streams | Output is clipped; the request still completes |

#### Database naming

A database is named `<tenant>-<database identifier>`. A database identifier carries no `-`, so the last `-` in a name separates the Tenant name from the identifier and no two Tenants resolve to the same database.

### Patterns

| Situation | Approach |
|-----------|----------|
| Any request data tenant code reads | Compose it into a value the Host builds and hands over, rather than a Handle to a Host object; a field the Host left out is unreachable rather than merely refused |
| Any Host object supplied into a Sandbox | Narrow the methods tenant code may call to an allow list; methods outside it are invisible by default |
| Any method name on a guest-reachable surface | Keep it clear of Ruby's ambient reflection surface — `method`, `send`, `class` and their kin are refused before any allow list is read |
| Any Binding that varies per request | Declare it pending when the Sandbox is built and supply it per invocation; an unsupplied call fails rather than falling back to a shared object |
| Any change to a Tenant's files | Discard and rebuild that Tenant's Sandbox rather than updating it in part |
| Any routing ambiguity | Treat it as not routable rather than guessing the target Tenant |
| Any disagreement between the shared directory and cached Host state | The shared directory governs |
| Any failure message returned to a tenant or outward | Carry at most the failure class and the tenant's own information |
| Any failure the Host caused rather than the Tenant | Record it where the operator reads, naming what could not be reached. The response is unchanged: a failure class alone cannot say whose fault it was, and only the operator can act on the difference |
