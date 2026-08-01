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


### Interpretation

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

### Smoke-Test Snapshots

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

### Inception Note

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

That shape maps naturally to hybrid runtimes where parallel workers own local
concurrent resource pools.

## Additonal PostgreSQL Runtime Verification

The smoke tests are demonstrations of correctness rather than benchmarks.

In addition to the application output, the following observations help verify
that `LocalPool` preserves ownership of live PostgreSQL connections while
allowing concurrent work.

### Operating System Threads

While the smoke test is running, observe the Ruby process:

```sh
ps -L -p $(pgrep -n ruby) \
  -o pid,tid,psr,pcpu,rss,nlwp,etimes,comm
```

Typical output:

```text
PID     TID     PSR %CPU   RSS NLWP ELAPSED COMMAND
868028  868028    1  0.2 44528    9     210 ruby
868028  868038    3  0.9 44528    9     210 ruby
868028  868062    2  1.1 44528    9     209 ruby
868028  868063    3  1.1 44528    9     209 ruby
868028  868068    3  1.1 44528    9     209 ruby
868028  871497    2  0.6 44528    9      51 ruby
868028  871498    3  0.5 44528    9      51 ruby
868028  871499    3  0.5 44528    9      51 ruby
868028  871509    3  0.5 44528    9      51 ruby
```

The exact number of native threads (`NLWP`) and resident memory (`RSS`, reported
by `ps` in KiB) may vary between Ruby versions and operating systems. CPU
migration (`PSR`) is expected and reflects normal operating system scheduling.

This observation confirms that the Ruby runtime remains healthy throughout the
smoke test. It is not intended to measure performance or prove parallel speedup.

### PostgreSQL Backend Sessions

While the smoke test is running, inspect PostgreSQL:

```sh
docker compose exec postgres \
  psql -U ratomic ratomic_smoke \
  -c "
SELECT pid,
       backend_start,
       usename,
       application_name,
       state
FROM pg_stat_activity
WHERE datname = 'ratomic_smoke'
  AND application_name != 'psql'
ORDER BY pid;
"
```

Typical output:

```text
 pid  |         backend_start         | usename |      application_name      | state
------+-------------------------------+---------+----------------------------+--------
 2339 | 2026-08-01 09:49:53.655536+00 | ratomic | postgres/queue_postgres.rb | active
 2340 | 2026-08-01 09:49:53.656342+00 | ratomic | postgres/queue_postgres.rb | active
 2341 | 2026-08-01 09:49:53.656982+00 | ratomic | postgres/queue_postgres.rb | active
 2342 | 2026-08-01 09:49:53.658075+00 | ratomic | postgres/queue_postgres.rb | active
 2343 | 2026-08-01 09:49:53.658455+00 | ratomic | postgres/queue_postgres.rb | idle
```

Multiple PostgreSQL backend sessions should appear while the consumers are
running. Active consumers repeatedly execute the queue-claim statement using
`FOR UPDATE SKIP LOCKED`, allowing work to be claimed concurrently while each
backend retains ownership of its own database connection.

This demonstrates that `Ratomic::LocalPool` reuses long-lived PostgreSQL
connections rather than continuously creating new ones, preserving resource
ownership throughout the lifetime of the smoke test.

### What This Demonstrates

Combined with the application output, these observations show:

- all producers complete successfully
- all consumers complete successfully
- queues drain to zero
- no `Ractor::MovedError`
- no `Ractor::IsolationError`
- PostgreSQL connections are reused rather than continuously recreated
- live database connections remain local to their owning execution context

Together, these observations validate the ownership and resource-locality
properties of `Ratomic::LocalPool`. They demonstrate that the shareable
`LocalPool` facade safely manages long-lived, Ractor-local resources such as
PostgreSQL connections. These smoke tests validate correctness, not performance.

The smoke tests are demonstrations of correctness rather than benchmarks.

In addition to the application output, the following observations help verify
that `LocalPool` preserves ownership of live PostgreSQL connections while
allowing concurrent work.
