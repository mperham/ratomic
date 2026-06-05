# Ratomic

[![Gem Version](https://badge.fury.io/rb/ratomic.svg)](https://badge.fury.io/rb/ratomic)
[![CI](https://github.com/mperham/ratomic/workflows/CI/badge.svg)](https://github.com/mperham/ratomic/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Ratomic provides mutable data structures for Ruby Ractors. Its primitives are backed by native Rust concurrency libraries so Ruby code can share useful state across Ractors without falling back to one global lock. `Pool` uses Ruby Ractor ownership-transfer primitives instead of the native Rust path.

## Project Direction

Ratomic focuses on practical Ractor-safe primitives with a small API surface, clear
ownership semantics, and honest documentation about sharp edges.

`Ratomic::Map` is the current priority: a Ruby-facing concurrent Hash powered by
DashMap, with atomic per-key operations designed for real Ractor workloads.

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

## Examples And Benchmarks

- [`redis_poc`](./redis_poc) contains local Redis scripts that exercise
  `Ratomic::Map`, `Ratomic::Counter`, and `Ratomic::Pool` under Thread and
  Ractor workloads.
- The [`cdc-parallel` Ratomic benchmark][cdc-parallel-ratomic] demonstrates
  Ractor workers updating shared CDC processing metrics through `Ratomic::Map`
  and `Ratomic::Counter`.

## Usage

Ratomic provides two safety models:

- `Counter`, `Map`, and `Queue` are shared concurrent structures.
- `Pool` transfers ownership of mutable objects between Ractors.

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

`Ratomic::Map` is a Ractor-safe concurrent Hash backed by Rust's DashMap. It is
not a full `Hash` replacement; iteration and arbitrary mutable object borrowing
are intentionally absent.

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

## Contributing

Please read the [Code of Conduct](./CODE_OF_CONDUCT.md) before contributing.

After changing code, run:

```bash
rake
```

This compiles the Rust code and runs the test suite. The test suite writes a
SimpleCov report to `coverage/index.html` for the Ruby wrapper paths.

## Thanks

[Ilya Bylich](https://github.com/iliabylich) wrote and documented his original
research at [Ruby, Ractors, and Lock-free Data Structures][ractor-research].

This repo continues that research into the usability and limitations of
Ractor-friendly structures in Ruby code and gems.

## License

[MIT License](https://opensource.org/licenses/MIT).

[cdc-parallel-ratomic]: https://github.com/kanutocd/cdc-parallel/blob/main/benchmark/RATOMIC.md
[ractor-research]: https://iliabylich.github.io/ruby-ractors-and-lock-free-data-structures/
