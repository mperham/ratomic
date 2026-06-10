# LocalPool Smoke Tests

This directory contains opt-in smoke tests for `Ratomic::LocalPool` with real
stateful network clients.

These scripts are demonstrations and smoke tests, not formal benchmarks. They
exist to show that live resources are created and reused inside the Ractor that
owns them while the `LocalPool` facade remains shareable.

## Services

Start Redis and PostgreSQL from this directory:

```sh
cd smoke_tests
docker compose up -d
```

Install the smoke-test bundle:

```sh
bundle install
```

Tear down services:

```sh
docker compose down
```

## Redis

Run repeated Redis operations from both Threads and Ractors:

```sh
bundle exec ruby redis/basic_redis.rb
```

Run the Redis producer/consumer queue smoke test:

```sh
TYPE=Thread bundle exec ruby redis/queue_redis.rb
TYPE=Ractor bundle exec ruby redis/queue_redis.rb
```

Useful knobs:

```sh
TIMES=50000 PRODUCERS=4 CONSUMERS=8 POOL_SIZE=8 TYPE=Ractor \
  bundle exec ruby redis/queue_redis.rb
```

## PostgreSQL

Run repeated PostgreSQL upserts from both Threads and Ractors:

```sh

```

Run the PostgreSQL producer/consumer table-queue smoke test:

```sh
TYPE=Thread bundle exec ruby postgres/queue_postgres.rb
TYPE=Ractor bundle exec ruby postgres/queue_postgres.rb
```

Useful knobs:

```sh
TIMES=5000 PRODUCERS=4 CONSUMERS=8 POOL_SIZE=8 TYPE=Ractor \
  bundle exec ruby postgres/queue_postgres.rb
```

Connection environment variables:

```sh
PGHOST=127.0.0.1
PGPORT=5432
PGDATABASE=ratomic_smoke
PGUSER=ratomic
PGPASSWORD=ratomic
```

## Interpretation

A successful smoke-test run should demonstrate:

- no `Ractor::MovedError`
- no `Ractor::IsolationError`
- no process crash
- all produced work is consumed
- Redis queues or PostgreSQL table queues drain to zero
- live clients/connections remain owned by the Ractor that created them

Redis proves the network-client shape. PostgreSQL proves the database-connection
shape. Together they demonstrate that `LocalPool` is not Redis-specific; it is a
resource-locality primitive for live stateful clients.

## Inception note

`LocalPool` is intentionally a small "inception pool":

```text
pool facade
  ↓
local pool
  ↓
resource
```

That shape maps naturally to hybrid runtimes where parallel workers own local
concurrent resource pools.

## Smoke-Test Snapshots

The following snapshots were captured using the default smoke-test
configuration.

These are not formal benchmarks. Their purpose is to validate correctness,
resource ownership, and queue-draining behaviour under both Thread and
Ractor execution.

### PostgreSQL Queue Smoke Test

#### Ractor

```text
[:start, Ractor, 2026-06-10 12:09:31.466037753 +0800]

[[:producer_done, 0], [:producer_done, 1]]

[[:consumer_done, 0, 8027],
 [:consumer_done, 1, 7994],
 [:consumer_done, 2, 8032],
 [:consumer_done, 3, 7962],
 [:consumer_done, 4, 7985]]

[{"one" => 0},
 {"two" => 0},
 {"three" => 0},
 {"four" => 0},
 {"five" => 0}]

[:end, 2026-06-10 12:13:59.39214017 +0800]
```

#### Thread

```text
NOTICE: relation "ratomic_smoke_jobs" already exists, skipping

[:start, Thread, 2026-06-10 12:16:23.800750901 +0800]

[[:producer_done, 0], [:producer_done, 1]]

[[:consumer_done, 0, 7999],
 [:consumer_done, 1, 7958],
 [:consumer_done, 2, 8016],
 [:consumer_done, 3, 8036],
 [:consumer_done, 4, 7991]]

[{"one" => 0},
 {"two" => 0},
 {"three" => 0},
 {"four" => 0},
 {"five" => 0}]

[:end, 2026-06-10 12:20:44.311706205 +0800]
```

### Interpretation

Both execution modes successfully:

* completed all producer workloads
* consumed all queued work
* drained every queue to zero
* reused PostgreSQL connections safely
* avoided `Ractor::MovedError`
* avoided `Ractor::IsolationError`

The PostgreSQL smoke tests demonstrate that `LocalPool` is not Redis-specific.
The same ownership-preserving design works for database connections, which are
another class of stateful resources that should remain local to the Ractor that
created them.

## What These Tests Validate

Redis validates:

* network-client locality
* connection reuse
* ownership preservation

PostgreSQL validates:

* database-connection locality
* transactional workloads
* queue-style coordination patterns

Together they demonstrate that `LocalPool` is a resource-locality primitive for
live stateful clients rather than a Redis-specific abstraction.

## Inception Note

`LocalPool` intentionally follows a small "inception pool" shape:

```text
pool facade
  ↓
local pool
  ↓
resource
```

The facade is shareable.

The live resource is not.

Work moves between Ractors. Live resources stay local.
