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
| Data binding | A tenant declares multiple SQLite Bindings in its Manifest and reads and writes them through named constants, and cannot reach another tenant's databases |
| Node visibility | The same request to the same tenant reads a different `Env.node` on different nodes, while its Binding reads and writes yield identical results |
| Failure containment | An exception, timeout, or memory exhaustion in tenant code affects only that request; the Host process and other tenants' requests are unaffected |
| Rack compatibility | Tenant code returns a Rack response triplet, which the Host hands to the HTTP layer without semantic translation |

### Success Criteria

| Criterion | Verification |
|-----------|--------------|
| Publishing needs no restart | Adding a tenant directory to a running Host makes `GET https://<domain>/<tenant>` respond 200 |
| The sandbox is closed | Tenant code's attempts to reach environment variables, the filesystem, and the network all fail, and the failures disclose no Host environment content |
| Tenants are isolated from each other | Tenant A's code cannot obtain any Binding declared by tenant B |
| Cross-node results agree | Across consecutive requests served by different nodes, `Env.node` differs while a query against the same Binding returns the same result |
| Writes work from every node | A request served by any node writes to its Binding successfully, and the write is visible to subsequent requests |
| Failures do not spread | While tenant code loops forever, that request ends 5xx and other tenants' requests keep responding normally |

### Non-Goals

- Billing, quotas, SLA management, and cross-tenant fairness scheduling
- A control-plane API and tenant authentication — the shared directory is the only deployment interface
- Bindings other than SQLite (KV, object storage, queues, durable objects)
- Schema definition and migration for tenant databases — tenant code creates its own tables
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
| **Worker** | The entrypoint constant defined by a Tenant's mruby source; accepts one Request and returns a Rack response triplet | In scope |
| **Binding** | A named Service supplied into the Sandbox — either `Env` or `DB` — and tenant code's only path outward | In scope |
| **Runtime Kit** | mruby helper objects the Host loads into every Sandbox, present regardless of Tenant files | In scope |
| **Node** | A cluster node running one Host instance; exactly one Node in the cluster is the SQLite Writer | In scope |
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
- Give the Sandbox the real clock and real randomness
- Pass a Request as the Worker's only argument and hand the returned triplet to the HTTP layer
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
- SQLite database files sit on a replicated filesystem mount that every Node carries, with single-Writer semantics and cross-Node read-after-write visibility
- External traffic reaches an internal cluster service through a tunnel service; the Host is not exposed to the public network directly

**Output guarantees:**

- Every request yields exactly one HTTP response; tenant code terminates the Host process under no outcome
- `Env.node` reflects the Node that actually executed that invocation
- Tenant code obtains the Host's environment variables, filesystem paths, and network connections under no circumstance

#### Control — what the Host controls / depends on

- **Controls:** route resolution, Sandbox lifecycle, the content and method surface of each Binding, the creation of each Binding's database file, and the mapping from failure to HTTP status
- **Depends on:** kobako's isolation and error classification, the Sandbox's mruby build providing JSON generation and Regexp, the replicated filesystem's single-Writer semantics and cross-Node read-after-write visibility, the readability of shared storage, Node-to-Node reachability inside the cluster, and the tunnel service's external connectivity

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
- **Outcome:** The query returns rows and the write is visible to later requests; the code cannot reach a Binding declared by another Tenant

#### J-03 — A technology evaluator compares cross-node behavior

- **Context:** The cluster has several Nodes and one Tenant is live
- **Action:** Issue consecutive requests to one endpoint and compare `Env.node` against the Binding query results
- **Outcome:** `Env.node` tracks the serving Node, queries against the same Binding agree, and writes succeed from any Node

#### J-04 — A platform operator deploys the cluster

- **Context:** A multi-node cluster is available, with a shared filesystem for the tenant directory and a replicated filesystem for the databases
- **Action:** Deploy the Host workload, mount the shared directory and the replicated filesystem, designate the Writer Node, and point the tunnel at the internal service
- **Outcome:** Requests to the external domain reach a Host on any Node and are answered; Nodes other than the Writer complete writes as well

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
| B-02 | A directory holds no `app.json` | The directory constitutes no Tenant and is not routable |
| B-03 | A Tenant directory holds several `*.rb` files | All are loaded into one Sandbox in lexicographic filename order, so a later file may reference constants an earlier one defined |
| B-04 | A Manifest or `*.rb` changes while the Host runs | The next request reaching that Tenant is served by the changed content |

### F-02 — Request routing

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-05 | The request path's first segment equals the Tenant name | Routes to that Tenant; the path the Worker receives has that segment removed |
| B-06 | The Manifest declares a domain + the request's Host header matches it | Routes to that Tenant; the path is passed through unchanged |
| B-07 | The Host's base domain is configured + the request's Host header is `<tenant>.<base>` | Routes to that Tenant; the path is passed through unchanged |
| B-08 | A request matches more than one form | Forms are matched in order: the Manifest `domain`, then `<tenant>.<base>`, then the path form |

### F-03 — Sandbox caching and lifecycle

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-09 | A Tenant is routed to for the first time | The Host creates a Sandbox, loads the Runtime Kit and that Tenant's `*.rb`, declares `Env` and each Manifest Binding as pending, then dispatches the entrypoint |
| B-10 | The Tenant has a Sandbox and its files are unchanged | That Sandbox serves the dispatch; source is not reloaded |
| B-11 | The Tenant's files have changed | The Tenant's Sandbox is discarded and rebuilt per B-09, then dispatched |
| B-12 | Concurrent requests to one Tenant | They share that Tenant's Sandbox; each invocation holds its own Bindings, output captures, and resource usage |
| B-13 | Any invocation ends | That invocation's supplied Bindings and output captures end with it and do not carry into the next |
| B-14 | Tenant code reads the clock or draws a random number | It obtains the real clock and real randomness; environment variables, filesystem paths, and network connections stay unreachable |

### F-04 — Env Binding

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-15 | Every invocation | The Host supplies `Env`, whose surface exposes the executing node's identity, whether that node is the Writer, the Tenant name, and the request identity |
| B-16 | Tenant code calls a method on `Env` outside the allow list | The call is refused, and the Host's environment variables are not disclosed by it |
| B-17 | Requests to one Tenant are served by different Nodes | Each invocation's `Env.node` reflects the Node that executed it |

### F-05 — DB Binding

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-18 | The Manifest declares a Binding + every invocation | The Host supplies the corresponding SQLite Binding under the declared constant name |
| B-19 | A declared Binding's database file does not exist + the Binding is supplied | The Host creates it through the Writer, then supplies it |
| B-20 | Tenant code queries a Binding | Returns an Array of rows, each a Hash of column name to value |
| B-21 | Tenant code writes to a Binding + the executing node is the Writer | The write completes and returns the affected row count |
| B-22 | Tenant code writes to a Binding + the executing node is not the Writer | The write is serialized through the Writer and then completes; what tenant code observes is indistinguishable from B-21 |
| B-23 | A later request queries the same Binding after a write | The query reflects that write, whichever Node serves it |
| B-24 | A statement a Tenant executes against a Binding fails in the database | The failure reaches tenant code as an exception it may rescue |
| B-25 | A Binding constant the Manifest does not declare | Tenant code does not see that constant |
| B-26 | A Tenant's Binding constant | Resolves only to a database that Tenant declared |

### F-06 — Runtime Kit

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-27 | Every Sandbox | The Runtime Kit loads before the Tenant's `*.rb`, so tenant code may use its constants at the top level |
| B-28 | Tenant code uses the Runtime Kit | It reads the Request as named fields and builds a Rack response triplet as plain text, as JSON, or with a chosen status code |
| B-29 | Tenant code returns a triplet directly without the Runtime Kit | Equally valid; the Host's handling is unchanged |
| B-30 | A Tenant's `*.rb` defines a constant that the Runtime Kit also defines | The Tenant's definition takes effect |

### F-07 — Failure containment and response mapping

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-31 | The Worker returns a valid Rack response triplet | The Host hands it to the HTTP layer unchanged |
| B-32 | Any failure in any Tenant | Other Tenants' requests are unaffected and the Host process keeps running |
| B-33 | A failure caused by the timeout or the memory limit | The Tenant's Sandbox is discarded and the next request rebuilds it per B-09 |
| B-34 | Any failure response | Carries the failure class, and carries no Host environment variable, filesystem path, or internal address |

### F-08 — Deployment topology

| ID | State + Operation | Result |
|----|-------------------|--------|
| B-35 | The Host workload runs on several Nodes + the shared directory is mounted on each | Every Node sees the same set of Tenants |
| B-36 | The replicated filesystem is mounted on each Node | Database files sit flat at the mount root |
| B-37 | The Writer is designated by configuration | The Writer does not move automatically with node state |
| B-38 | The Writer is unavailable | Reads stay available; writes fail |
| B-39 | The tunnel service points at the internal service | Requests to the external domain reach a Host on any Node |

### Error Scenarios

| ID | Trigger | Response |
|----|---------|----------|
| E-01 | Neither the Host header nor the path's first segment matches a Tenant | 404 |
| E-02 | A Manifest is not a JSON object | The Tenant is not routable and its endpoints answer 404; the Host records the Tenant as invalid |
| E-03 | Two Tenants declare the same domain | Neither is routable and both endpoints answer 404 |
| E-04 | A Tenant's `*.rb` fails to compile | 500 carrying the failure class |
| E-05 | No `*.rb` defines the entrypoint constant the Manifest names | 500 listing the top-level constants that are available |
| E-06 | Tenant code raises an exception it does not rescue | 500 carrying the failure class |
| E-07 | The Worker's return value is not a valid Rack response triplet | 500 |
| E-08 | Tenant code exceeds the timeout | 503 marked as a timeout |
| E-09 | Tenant code exhausts the memory limit | 503 marked as a memory limit |
| E-10 | A pending Binding is called before it is supplied | 500 |
| E-11 | A Binding's database file cannot be created or opened | 500 carrying the failure class |
| E-12 | A write from a non-Writer node cannot reach the Writer | 500 |
| E-13 | The shared directory is unreadable | Every Tenant endpoint answers 503 |

---

## Refinement

### Terminology

| Term | Meaning |
|------|---------|
| **Host** | The workers-rb process running on one Node. "Host" always names this process, never HTTP's Host header, which is written "Host header" throughout |
| **Tenant** | One application unit under the shared directory, identified by its directory name |
| **Manifest** | `/app/<tenant>/app.json` |
| **Worker** | The callable that the entrypoint constant named by the Manifest refers to |
| **Binding** | A named Service supplied into a Sandbox. `Env` carries node and request information; `DB::*` carries a SQLite database |
| **Runtime Kit** | The mruby helper objects the Host loads into every Sandbox |
| **Node** | A cluster node running one Host |
| **Writer** | The single Node that may write SQLite, designated by configuration |
| **invocation** | One entrypoint call the Host makes into a Sandbox, corresponding to exactly one HTTP request |
| **failure class** | The category a failure response carries: compile failure, tenant exception, invalid response, timeout, memory limit, or binding failure |
| **supply** | The Host's act of providing a Binding object for the span of one invocation. A pending Binding that is called before it is supplied fails |

### Contracts

#### Host configuration

The operator supplies these to each Host as environment variables. They are cluster-level; a Manifest does not alter them.

| Setting | Meaning |
|---------|---------|
| Base domain | The suffix under which `<tenant>.<base>` resolves per B-07 |
| Shared directory | The mount path holding `/app/<tenant>/` |
| Database mount | The replicated filesystem mount root holding the database files |
| Writer designation | Whether this Node is the Writer |

#### Manifest

Every field is optional; an empty object is a valid Manifest. `bindings` appears only when the Tenant needs a database.

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

#### Worker entrypoint

The entrypoint constant is a callable accepting one Request and returning a Rack response triplet.

```ruby
App = ->(request) {
  [200, { "content-type" => "text/plain" }, ["hello from #{Env.node}\n"]]
}
```

| Position | Shape |
|----------|-------|
| Argument | One Request |
| Returned `status` | Integer |
| Returned `headers` | Hash of String keys to String values |
| Returned `body` | Array of String |

#### Guest-reachable method surface

Calls to methods outside these tables are refused per B-16.

| Binding | Method | Returns |
|---------|--------|---------|
| Request | `method` | The HTTP method as a String |
| Request | `path` | The path as a String, with the Tenant segment removed under path-form routing |
| Request | `query` | A Hash of query parameters |
| Request | `headers` | A Hash of request headers |
| Request | `body` | The request body as a String |
| `Env` | `node` | The identity of the Node that executed this invocation |
| `Env` | `writer?` | Whether that Node is the Writer |
| `Env` | `tenant` | The Tenant name |
| `Env` | `request_id` | The identity of this request |
| `DB::*` | `query(sql, *params)` | An Array of rows, each a Hash of column name to value |
| `DB::*` | `execute(sql, *params)` | The affected row count |

A row's values reach tenant code as Integer, Float, String, or nil.

#### Execution limits

One set of limits applies to every Tenant; a Manifest does not alter them.

| Limit | Value | On exhaustion |
|-------|-------|---------------|
| Wall clock per invocation | 5 seconds | E-08 |
| Memory per invocation | 16 MiB | E-09 |
| Captured output per invocation | 64 KiB each for the standard output and error streams | Output is clipped; the request still completes |

#### Database file naming

A database file is `<tenant>-<database identifier>.db` at the root of the replicated filesystem mount. The mount holds no subdirectories.

### Patterns

| Situation | Approach |
|-----------|----------|
| Any Host object supplied into a Sandbox | Narrow the methods tenant code may call to an allow list; methods outside it are invisible by default |
| Any Binding that varies per request | Declare it pending when the Sandbox is built and supply it per invocation; an unsupplied call fails rather than falling back to a shared object |
| Any change to a Tenant's files | Discard and rebuild that Tenant's Sandbox rather than updating it in part |
| Any routing ambiguity | Treat it as not routable rather than guessing the target Tenant |
| Any failure message returned to a tenant or outward | Carry only the failure class and the tenant's own information |
