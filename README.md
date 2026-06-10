# Ratomic

[![Gem Version](https://badge.fury.io/rb/ratomic.svg)](https://badge.fury.io/rb/ratomic)
[![CI](https://github.com/mperham/ratomic/workflows/CI/badge.svg)](https://github.com/mperham/ratomic/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Ratomic provides mutable data structures for Ruby Ractors. Its core shared primitives are backed by native Rust concurrency libraries so Ruby code can share useful state across Ractors without falling back to one global lock. `Pool` and `LocalPool` are pure Ruby primitives that use Ruby Ractor ownership and locality semantics instead of the native Rust path.

## Project Direction

Ratomic focuses on practical Ractor-safe primitives with a small API surface, clear
ownership semantics, and honest documentation about sharp edges.

## Requirements

- Ruby 4.0 or newer
- Bundler
- Rust toolchain when building the native extension from source

## Installation

Add Ratomic to your application's Gemfile:

```bash
bundle add ratomic
```

Then require it from Ruby:

```ruby
require "ratomic"
```

## Documentation

API documentation is published to GitHub Pages:

- [mperham.github.io/ratomic](https://mperham.github.io/ratomic/)

RBS signatures are included under `sig/` for downstream type checking.

## Examples And Benchmarks

- [`smoke_tests`](./smoke_tests) contains local Redis and PostgreSQL scripts that
  exercise `Ratomic::LocalPool` with real stateful clients under Thread and
  Ractor workloads.
- [`pgoutput-parser`](https://github.com/kanutocd/pgoutput-parser#relation-metadata-tracking)
  uses `Ratomic::Map` for relation metadata tracking in a real CDC pipeline
  POC, with a matching benchmark and deeper implementation notes in
  [docs/relation_tracker.md](https://github.com/kanutocd/pgoutput-parser/blob/main/docs/relation_tracker.md).
- [`sidekiq-tenant-policy-cache`](https://github.com/kanutocd/sidekiq-tenant-policy-cache)
  shows `Ratomic::Map` and `Ratomic::Counter` in Sidekiq middleware for tenant
  policy caching and cache-hit / cache-miss tracking, with a benchmarked
  cache-vs-policy-every-job comparison.
- The [`cdc-parallel` Ratomic benchmark][cdc-parallel-ratomic] demonstrates
  Ractor workers updating shared CDC processing metrics through `Ratomic::Map`
  and `Ratomic::Counter`.

## Usage

Ratomic provides three safety models:

- `Counter`, `Map`, and `Queue` are shared concurrent structures.
- `Pool` transfers ownership of plain mutable objects between Ractors.
- `LocalPool` keeps live resources local to the Ractor that created them.

That distinction matters. A mutable pooled object is not shared by multiple Ractors
at the same time. It is moved to the caller on checkout and moved back to the pool
on checkin.

These structures are designed for use as class-level constants so they can be
shared by many Ractors.

### `Ratomic::Counter`

`Ratomic::Counter` is a Ractor-shareable atomic counter.

```ruby
counter = Ratomic::Counter.new

counter.read # => 0
counter.increment(1)
counter.increment(5)
counter.decrement(1)
counter.decrement(1)

counter.read # => 4
counter.to_i # => 4
counter.zero? # => false
```

### `Ratomic::Map`

`Ratomic::Map` is the primary Ractor-safe concurrent Hash primitive in Ratomic.
It is backed by Rust's DashMap and provides atomic per-key operations for real
Ractor workloads. It is not a full `Hash` replacement; iteration and arbitrary
mutable object borrowing are intentionally absent.

```ruby
OFFSETS = Ratomic::Map.new

OFFSETS["mike"] = 123
OFFSETS["mike"] # => 123
OFFSETS.key?("mike") # => true
OFFSETS.fetch("missing", 0) # => 0

OFFSETS.fetch_or_store("count") { 0 } # => 0
OFFSETS.compute("mike") { |value| value + 1 } # => 124
OFFSETS.upsert("mike", 1) { |value| value + 1 } # => 125
OFFSETS.fetch_and_modify("mike") { |value| value + 1 }

OFFSETS.delete("mike") # => 126
OFFSETS.length
OFFSETS.empty?
OFFSETS.clear
```

`Map` also includes atomic convenience methods for common bucket patterns:

```ruby
counts = Ratomic::Map.new
counts.increment("jobs") # => 1
counts.decrement("jobs") # => 0

groups = Ratomic::Map.new
groups.append("jobs", "import") # => ["import"]
groups.add_to_set("workers", "alpha") # => #<Set: {"alpha"}>
```

Some `Map` methods hold an internal guard while a block runs or while a
reference is live. Avoid re-entering the same map from inside those blocks or
mutating the same key while holding a reference from `get` or `[]`. The API
docs cover the exact locking caveats.

### `Ratomic::Queue`

`Ratomic::Queue` is a Ractor-shareable multi-producer, multi-consumer queue.

```ruby
queue = Ratomic::Queue.new(128)

queue.push("hello")
queue << "world"

queue.size # => 2
queue.empty? # => false
queue.peek # => "hello"
queue.pop # => "hello"
queue.pop # => "world"
queue.empty? # => true
```

The `.new(capacity)` method initializes the queue with a fixed-size buffer.
Capacity must be at least `1` and at most `2**20`. Non-power-of-two capacities
are supported exactly.

Since `Ratomic::Queue` is concurrent, `size`, `empty?`, and `peek` are
moment-in-time observations. Their results may already be stale by the time your
code uses them.

### `Ratomic::Pool`

`Ratomic::Pool` is a Ractor-safe ownership-transfer pool for mutable Ruby objects.

```ruby
BUFFERS = Ratomic::Pool.new(5, 1.0) { [] }

BUFFERS.with do |buffer|
  buffer.clear
  buffer << "work"
end
```

`Pool` uses Ruby 4's `Ractor::Port` and `move: true` semantics so only one
Ractor owns a checked-out object at a time.

When an object is checked out:

- the pool moves the object to the caller
- the caller can mutate the object while it owns it
- the pool cannot hand that object to another Ractor until it is checked in

When an object is checked in:

- ownership moves back to the pool
- stale references held by the caller become moved objects
- using those stale references raises `Ractor::MovedError`

This means incorrect usage fails at the Ruby object-ownership boundary rather
than allowing two Ractors to mutate the same object concurrently.

```ruby
outside = nil

BUFFERS.with do |buffer|
  outside = buffer
  buffer << "inside"
end

outside << "outside"
# raises Ractor::MovedError
```

Manual checkout and checkin are also supported:

```ruby
buffer = BUFFERS.checkout
raise "pool checkout timeout" if buffer.nil?

begin
  buffer << "manual work"
ensure
  BUFFERS.checkin(buffer) if buffer
end
```

`checkout` returns `nil` if no pooled object becomes available before the
configured timeout. `with` raises `Ratomic::Error` in that case.

`Pool` uses ownership transfer, not Rust's full borrow checker:

- the Rust owner maps to the Ractor that currently checked out the pooled object
- the Rust move maps to `Ractor::Port#send(..., move: true)`
- Rust's "cannot use after move" rule maps to Ruby raising `Ractor::MovedError`
- borrowing is not modeled; `Pool` transfers ownership instead of lending references

This design addresses [issue #5](https://github.com/mperham/ratomic/issues/5),
where using a pooled object after `with` could lead to memory corruption or a
process crash.

The lower-level `Ratomic::FixedSizeObjectPool` native class may still exist, but
`Ratomic::Pool` does not inherit from it. The public `Pool` API is implemented
in Ruby so it can use Ruby's Ractor ownership primitives directly.


### `Ratomic::LocalPool`

`Ratomic::LocalPool` is the safe pool shape for live resources that should stay
local to the Ractor that created them.

Use it for resources such as:

- Redis clients
- database connections
- HTTP clients
- Kafka producers
- OpenSearch clients
- per-worker caches, buffers, encoders, or aggregators

Unlike `Ratomic::Pool`, `LocalPool` does **not** move pooled objects between
Ractors. The `LocalPool` instance is a shareable facade. Each Ractor lazily
creates and owns its own private, thread-safe resource pool behind that facade.
Threads inside the same Ractor share that local pool, but different Ractors
never share the live resources.

```ruby
require "ratomic"
require "redis-client"

RedisFactory = Data.define(:host) do
  def call
    RedisClient.new(host: host)
  end
end

REDIS = Ratomic::LocalPool.new(
  size: 10,
  timeout: 1,
  factory: RedisFactory.new("127.0.0.1".freeze)
)

REDIS.with do |client|
  client.call("ping")
end
```

Use `Pool` for plain mutable values where ownership transfer is the intended
safety model. Use `LocalPool` for live resources that should be created, used,
and reused inside the same Ractor.

The intended topology is:

```text
shareable LocalPool facade
        ↓
one local resource pool per Ractor
        ↓
threads inside that Ractor share local resources
```

The mental model is intentionally close to a Ruby local variable: the resource is
local to the execution scope that owns it. For `LocalPool`, that scope is the
current Ractor.

#### Pure Ruby implementation

`LocalPool` is implemented in pure Ruby.

Unlike `Counter`, `Map`, and `Queue`, it is not backed by the Rust native
extension. Its safety comes from Ruby Ractor ownership boundaries and locality,
not from Rust synchronization primitives.

#### Why not use `Pool` for Redis clients?

`Pool` moves checked-out objects between Ractors. That is correct for plain
mutable Ruby values such as arrays or buffers, but it is a poor fit for live I/O
resources. Redis clients, database connections, sockets, and similar resources
carry internal connection state. Moving those objects across Ractor boundaries can
leave nested internal state unusable, producing errors such as
`Ractor::MovedError`.

`LocalPool` avoids that class of bug by not moving live resources at all. Work
moves between Ractors. Live resources stay local.

#### Redis and PostgreSQL smoke-test snapshots

The smoke tests live under [`smoke_tests/`](./smoke_tests/) and exercise `LocalPool` with real
Redis clients and PostgreSQL connections.

`redis/basic_redis.rb` exercises repeated Redis operations from both Threads and
Ractors:

```text
Thread
[{"one" => 31501}, {"two" => 31379}, {"three" => 31320}, {"four" => 31410}, {"five" => 31454}]

Ractor
[{"one" => 42419}, {"two" => 42186}, {"three" => 42400}, {"four" => 42206}, {"five" => 42568}]
```

`redis/queue_redis.rb` exercises a producer/consumer Redis queue workload:

```text
[:start, Ractor, 2026-06-10 01:17:57.584727984 +0800]
[[:producer_done, 0], [:producer_done, 1]]
[[:consumer_done, 0, 7998], [:consumer_done, 1, 7987], [:consumer_done, 2, 7984], [:consumer_done, 3, 8035], [:consumer_done, 4, 7996]]
[{"one" => 0}, {"two" => 0}, {"three" => 0}, {"four" => 0}, {"five" => 0}]
[:end, 2026-06-10 01:18:02.226310862 +0800]
```

`postgres/basic_postgres.rb` exercises repeated PostgreSQL upserts from both
Threads and Ractors. `postgres/queue_postgres.rb` exercises a table-backed
producer/consumer workload using `FOR UPDATE SKIP LOCKED`.

These numbers are smoke-test snapshots, not formal benchmark claims. The
important interpretation is:

- no `Ractor::MovedError`
- no `Ractor::IsolationError`
- no process crash
- all produced queue items were consumed
- Redis queues and PostgreSQL table queues drained to zero
- live Redis clients and PostgreSQL connections remained owned by the Ractor
  that created them

Redis proves the network-client shape. PostgreSQL proves the database-connection
shape. Together they demonstrate that `LocalPool` is not Redis-specific; it is a
resource-locality primitive for live stateful clients.

#### Inception pool

Internally, `LocalPool` follows the "inception pool" shape discovered while
experimenting with Redis clients under Ruby Ractors:

```text
pool facade
  ↓
local pool
  ↓
resource
```

That same ownership pattern appears in hybrid execution runtimes: put parallel
workers on the outside, keep I/O concurrency and live resources inside the worker
that owns them. Ratomic keeps the primitive general-purpose and independent of
any specific runtime, scheduler, database, or message system.

`LocalPool#close` closes only the current Ractor's local pool. Other Ractors own
their own pools and must close them independently when needed.

## Contributing

Please read the [Code of Conduct](./CODE_OF_CONDUCT.md) before contributing.

After changing code, run:

```bash
bundle exec rake
```

This compiles the Rust code and runs the test suite. The test suite writes a
SimpleCov report to `coverage/index.html` for the Ruby wrapper paths.

If you change the public Ruby API, update the curated RBS signatures under
`sig/ratomic.rbs` and run `bundle exec rake rbs:validate` before release or
review.

## Thanks

[Ilya Bylich](https://github.com/iliabylich) wrote and documented his original
research at [Ruby, Ractors, and Lock-free Data Structures][ractor-research].

This repo continues that research into the usability and limitations of
Ractor-friendly structures in Ruby code and gems.

## License

[MIT License](https://opensource.org/licenses/MIT).

[cdc-parallel-ratomic]: https://github.com/kanutocd/cdc-parallel/blob/main/benchmark/RATOMIC.md
[ractor-research]: https://iliabylich.github.io/ruby-ractors-and-lock-free-data-structures/
