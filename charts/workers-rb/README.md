# workers-rb

Asks Kubernetes for the shape the platform needs: several Hosts reading one
shared directory, one database server they all name, and one internal address.

## Install

<!-- x-release-please-start-version -->
```sh
helm install workers-rb oci://ghcr.io/elct9620/workers-rb \
  --version 0.4.0 \
  --set sharedDirectory.existingClaim=tenants
```
<!-- x-release-please-end -->

Each release publishes the chart under the repository's own reference and the
Host's image under `workers-rb/host`, at one version, so the two never
disagree about what is running. Installing the chart is what names the Host,
and nothing has to be told which image goes with it. `--version` is what pins
a cluster to one; without it Helm takes whatever is newest, which is not the
same answer next month.

A change that has not been released yet installs from a clone, and has to be
told which Host to run because the one it would otherwise name does not exist
under that version:

```sh
helm install workers-rb charts/workers-rb \
  --set image.tag=main \
  --set sharedDirectory.existingClaim=tenants
```

Upgrade with `--reset-then-reuse-values`. `--reuse-values` carries the old
values forward and never sees a default the new version added.

## What this chart leaves to you

`sharedDirectory.existingClaim` has no default, and the install stops until it
is named. The chart creates no claim of its own.

The chart installs no Gateway either. It creates the internal Service, and
`helm install` prints the address to point a tunnel, reverse proxy, or load
balancer at. `Env.node` reports the Pod's name, so it changes when the Hosts
are rolled.

Every setting carries its reasoning in [`values.yaml`](values.yaml) beside the
value it decides — including why these two are yours rather than the chart's.

## Health

Each Host answers `/_health/live` and `/_health/ready`: the first says the
process is up, the second that this Host reads the shared directory, which is
what a Pod that should be passed over gets wrong on its own.

Both are the Host's on every hostname, so a Gateway pointed at the Service
carries them on every Tenant's domain. Turning them away there is yours to do.

## Sizing the database server

Two settings decide how much a cluster can ask of one database server. The
numbers below are the demo's; the way to arrive at yours is what matters,
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
— so the log grows for as long as the load lasts, whatever
`databases.checkpointIntervalSeconds` is set to. What the interval decides is
how soon a quiet moment is used to reclaim it.

```
b = write-ahead log bytes per write statement
    run N writes, read dbs/<namespace>/data-wal, divide by N

headroom per database ≈ b × w × D
    w = peak write statements per second
    D = the longest stretch of saturation you expect

databases.checkpointIntervalSeconds ≤ the shortest quiet gap your traffic has
```

Measured on the demo: `b` ≈ 2 KB, and a log that reached 35 MB under
continuous writes was back to zero within 30 seconds of the writes stopping.
