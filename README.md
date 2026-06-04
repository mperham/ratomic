# Ratomic

[![Gem Version](https://badge.fury.io/rb/ratomic.svg)](https://badge.fury.io/rb/ratomic)
[![CI](https://github.com/mperham/ratomic/workflows/CI/badge.svg)](https://github.com/mperham/ratomic/actions)
[![Coverage Status](https://codecov.io/gh/mperham/ratomic/branch/main/graph/badge.svg)](https://codecov.io/gh/mperham/ratomic)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Ratomic provides mutable data structures for use with Ruby's Ractors.
This allows Ruby code to scale beyond the infamous GVL.

## Project direction

Ratomic is focused on practical Ractor-safe primitives backed by proven Rust concurrency libraries.

`Ratomic::Map` is the current priority: a Ruby-facing concurrent Hash powered by DashMap, with atomic per-key operations designed for real Ractor workloads. We are building from that foundation carefully, with a small API surface, clear ownership semantics, and honest documentation about the limits of each primitive.

Our core principles are honesty and transparency: document tradeoffs, name sharp edges, keep APIs small until their behavior is proven, and prefer established Rust concurrency libraries where they fit Ruby's Ractor semantics.

## How to contribute

Please make sure to understand our [Code of Conduct](./CODE_OF_CONDUCT.md).

After changing code, you can give it a spin with:

```bash
rake
```

This should compile the Rust code and run all tests.
The test suite writes a SimpleCov report to `coverage/index.html` so you can see which Ruby wrapper paths are covered.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add ratomic
```

## Usage

Ratomic provides several useful Ractor-safe structures.
Note the APIs available are frequently very limited compared to Ruby's broad API.

These structures are designed for use as class-level constants so they can be shared by numerous Ractors.

Ratomic has two different safety models:

* `Counter`, `Map`, and `Queue` are shared concurrent structures.
* `Pool` transfers ownership of mutable objects between Ractors.

That distinction matters. A mutable pooled object is not shared by multiple Ractors at the same time. It is moved to the caller on checkout and moved back to the pool on checkin.

### `Ratomic::Counter`

```ruby
c = Ratomic::Counter.new
c.read # => 0
c.inc
c.inc(5)
c.dec(1)
c.dec
c.read # => 4
c.to_i # => 4
c.zero? # => false
```

### `Ratomic::Pool`

A Ractor-safe object pool:

```ruby
POOL = Ratomic::Pool.new(5, 1.0) { [] }
POOL.with do |obj|
  # do something with obj
  obj << "work"
end
```

`Pool` is an ownership-transfer pool for mutable Ruby objects. It uses Ruby 4's `Ractor::Port` and `move: true` semantics so only one Ractor owns a checked-out object at a time.

This design addresses [issue #5](https://github.com/mperham/ratomic/issues/5), where using a pooled object after `with` could lead to memory corruption or a process crash. The fix is Rust-inspired ownership transfer, not Rust's full borrow checker: Ruby enforces the boundary dynamically at runtime through Ractor move semantics, while Rust enforces ownership and borrowing statically at compile time.

In that model:

* the Rust owner maps to the Ractor that currently checked out the pooled object
* the Rust move maps to `Ractor::Port#send(..., move: true)`
* Rust's "cannot use after move" rule maps to Ruby raising `Ractor::MovedError`
* borrowing is not modeled; `Pool` transfers ownership instead of lending references

When an object is checked out:

* the pool moves the object to the caller
* the caller can mutate the object while it owns it
* the pool cannot hand that object to another Ractor until it is checked in

When an object is checked in:

* ownership moves back to the pool
* stale references held by the caller become moved objects
* using those stale references raises `Ractor::MovedError`

This means incorrect usage fails at the Ruby object-ownership boundary rather than allowing two Ractors to mutate the same object concurrently.

```ruby
outside = nil

POOL.with do |obj|
  outside = obj
  obj << "inside"
end

outside << "outside"
# raises Ractor::MovedError
```

The lower-level `Ratomic::FixedSizeObjectPool` native class may still exist, but `Ratomic::Pool` does not inherit from it. The public `Pool` API is implemented in Ruby so it can use Ruby's Ractor ownership primitives directly.

Manual checkout/checkin is also supported:

```ruby
obj = POOL.checkout
raise "pool checkout timeout" if obj.nil?

begin
  obj << "manual work"
ensure
  POOL.checkin(obj) if obj
end
```

`checkout` returns `nil` if no pooled object becomes available before the configured timeout. `with` raises `Ratomic::Error` in that case.

### `Ratomic::Map`

A Ractor-safe concurrent Hash backed by Rust's DashMap:

```ruby
HASH = Ratomic::Map.new
HASH["mike"] = 123
HASH["mike"] # => 123
HASH.key?("mike") # => true
HASH.fetch("missing", 0) # => 0
HASH.fetch_or_store("count") { 0 } # => 0
HASH.compute("mike") { |value| value + 1 } # => 124
HASH.upsert("mike", 1) { |value| value + 1 } # => 125
HASH.fetch_and_modify("mike") { |value| value + 1 }
HASH.delete("mike") # => 126
HASH.length
HASH.empty?
HASH.clear
```

### `Ratomic::Queue`

A multi-producer, multi-consumer queue.

```ruby
q = Ratomic::Queue.new(128)

q.push("hello")
q << "world"

q.size     # => 2
q.empty?   # => false
q.peek     # => "hello"
item = q.pop # => "hello"
item = q.pop # => "world"
q.empty?   # => true
```
The `.new(capacity)` method initializes the queue with a fixed-size buffer. The capacity must be greater than or equal to 1 and less than or equal to 2<sup>20</sup>. Non-power-of-two capacities are supported exactly.

Since `Ratomic::Queue` is a concurrent queue, the `size`, `empty?`, and `peek` methods provide only a best-effort guess — the values they return might be stale or incorrect.

## Thanks

[Ilya Bylich](https://github.com/iliabylich) wrote and documented his original research at [Ruby, Ractors, and Lock-free Data Structures/](https://iliabylich.github.io/ruby-ractors-and-lock-free-data-structures/).
Thank you for your impressive work, Ilya!

This repo is further research into the usability and limitations of Ractor-friendly structures in Ruby code and gems.

## License

[MIT License](https://opensource.org/licenses/MIT).
