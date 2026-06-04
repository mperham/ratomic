# Ratomic::Map DashMap Roadmap

> `Ratomic::Map` is a hidden gem in ratomic: a Ractor-safe concurrent Hash
> backed by Rust's DashMap. The goal is not to expose DashMap directly. The goal
> is to expose Ruby-shaped APIs that make DashMap's concurrent entry operations
> useful and safe from Ruby Ractors.
>
> In other words: this is the dash road. Fast lanes, clear signs, no exposed
> guard rails.

## Positioning

`Ratomic::Map` should be described as:

> A Ractor-safe concurrent Hash backed by Rust's DashMap.

That gives the primitive a clear identity:

- familiar Ruby Hash-style ergonomics
- concurrent reads and writes from multiple Ractors
- atomic per-key operations that ordinary Ruby Hash cannot safely provide across Ractors
- native Rust performance without exposing Rust guard lifetimes to Ruby callers

This is the part of ratomic where the map is not just the territory; it is the
shortcut through traffic.

## Design Rules

- Keep DashMap as the implementation detail.
- Expose Ruby values, not DashMap guards or references.
- Prefer block APIs for atomic per-key behavior.
- Preserve Ruby `hash` and `eql?` semantics for keys.
- Preserve Ruby GC marking for all stored keys and values.
- Preserve Ractor-shareable typed-data behavior.
- Propagate Ruby exceptions from blocks; never unwrap and panic across Ruby boundaries.
- Avoid full Hash compatibility unless the behavior is coherent under concurrency.
- Treat `nil` as a normal Ruby value only after the missing-value story is explicit.

## Phase 1: Hash-Shaped Basics

These methods make `Ratomic::Map` feel like a practical Ruby map without exposing
DashMap internals.

- [x] `key?(key)`
- [x] `include?(key)`
- [x] `member?(key)`
- [x] `delete(key)`
- [x] `fetch(key, default = Ratomic::Undefined) { ... }`

### Notes

`key?`, `include?`, and `member?` can be aliases.

`delete` should remove the entry and return the previous value, or `nil` if the
key is absent. This matches Ruby Hash ergonomics, but it preserves the current
ambiguity around stored `nil`.

`fetch` should use `Ratomic::Undefined` internally so a missing key can be
distinguished from a stored `nil`.

This phase is the on-ramp: boring by design, necessary before the fast stuff.

## Phase 2: Concurrent Superpowers

These methods are where DashMap matters most. They should be prioritized over
large Hash compatibility.

- [ ] `fetch_or_store(key) { ... }`
- [x] `compute(key) { |old_value| ... }`
- [ ] `upsert(key, initial) { |old_value| ... }`

### `fetch_or_store`

Primary use case: Ractor-safe cache initialization.

```ruby
CACHE = Ratomic::Map.new

value = CACHE.fetch_or_store(user_id) do
  expensive_lookup(user_id)
end
```

Expected behavior:

- if the key exists, return the existing value
- if the key is absent, evaluate the block and store its result
- under contention, only one value should win storage for a key
- callers should receive the stored value
- block exceptions should propagate and leave the map unchanged

Implementation question:

DashMap can avoid a global lock, but Ruby block execution must be handled
carefully. Holding a DashMap shard lock while running arbitrary Ruby code may
create avoidable contention or reentrancy hazards. Prefer an implementation that
keeps native locks scoped tightly around map access.

This is the cache lane: one Ractor pays the toll, everyone else takes the
express route.

### `compute`

Primary use case: atomic per-key transformation.

```ruby
COUNTS.compute(:jobs) { |old| old.to_i + 1 }
```

Expected behavior:

- yields the current value or `nil` if absent
- stores the block return value
- returns the new value
- propagates block exceptions and leaves the previous value unchanged

This can become the general replacement for narrower mutation APIs.

This is where the map earns its racing stripes: read, decide, replace, all as
one coherent per-key move.

### `upsert`

Primary use case: initialize if missing, modify if present.

```ruby
COUNTS.upsert(:jobs, 1) { |old| old + 1 }
```

Expected behavior:

- if absent, store and return `initial`
- if present, yield old value, store block result, return block result
- propagate block exceptions and leave the previous value unchanged

## Phase 3: Domain Helpers

These methods turn common concurrent-map patterns into obvious Ruby APIs.

- [ ] `increment(key, by = 1)`
- [ ] `decrement(key, by = 1)`
- [ ] `append(key, value)`
- [ ] `add_to_set(key, value)`

### Counters And Histograms

```ruby
COUNTS.increment(:processed)
COUNTS.increment [:source_a, :success], 10
```

This is useful for metrics, progress counters, histograms, and per-key state.
The method should raise a clear Ruby exception if the existing value is not
numeric.

Counters are the odometer: small numbers, constant updates, no reason to make
every caller build the same machinery.

### Registries And Buckets

Helpers like `append` and `add_to_set` may be useful, but they need careful
Ractor semantics. Mutating an Array or Set stored inside the map can violate the
simple "values are shareable or safely moved" story. Prefer replacing stored
values over mutating them in place unless the value is known to be safe.

## Phase 4: Iteration And Snapshots

Iteration is useful, but it is easy to overpromise under concurrency.

- [ ] `each_pair`
- [ ] `to_h`
- [ ] `keys`
- [ ] `values`

### Rules

- Document these as best-effort snapshots or weakly consistent iteration.
- Do not hold native locks while yielding to Ruby blocks.
- Prefer collecting a snapshot of raw keys and values, then yielding outside
  DashMap locks.
- Make GC marking and Ractor shareability constraints explicit in tests.

Snapshots are dashboard photos, not traffic cameras. Useful, but not a promise
that the road stayed empty after the shutter clicked.

## Safety Checklist For Every New Method

- [ ] Does it preserve Ruby `hash` and `eql?` key semantics?
- [ ] Are all returned values valid Ruby `VALUE`s?
- [ ] Are stored keys and values marked for GC?
- [ ] Does it avoid yielding to Ruby while holding long-lived native locks?
- [ ] Does it propagate Ruby exceptions normally?
- [ ] If a block raises, is the map left in a coherent state?
- [ ] Is missing-key behavior distinct from stored `nil` where needed?
- [ ] Is the behavior meaningful under concurrent Ractor access?
- [ ] Is there focused unit coverage?
- [ ] Is there at least one Ractor behavior test for atomic APIs?

## Suggested Implementation Order

1. Add `key?`, `include?`, `member?`, and `delete`.
2. Add `fetch` with `Ratomic::Undefined` missing-value handling.
3. Add `fetch_or_store` with contention tests.
4. Add `compute` as the general atomic update primitive.
5. Add `increment` and `decrement` on top of `compute`.
6. Revisit iteration only after the mutation APIs are stable.

Follow the lanes in order. The fast path is faster when the road is paved first.

## Good First PRs

These are small enough to review independently and useful enough to move the
map forward immediately.

- `Map#key?` plus `include?` and `member?` aliases.
- `Map#delete` with unit coverage for present, missing, and stored-`nil` values.
- `Map#fetch` using `Ratomic::Undefined` to distinguish missing keys.
- README copy that says plainly: `Ratomic::Map` is a Ractor-safe concurrent Hash
  backed by Rust's DashMap.

The best PRs keep the Ruby API boring and let DashMap do the zooming underneath.

## Non-Goals For Now

- Full Ruby Hash compatibility.
- Exposing DashMap guards.
- Exposing shard-level APIs.
- Supporting arbitrary in-place mutation of stored mutable objects.
- Promising strongly consistent iteration during concurrent mutation.

## Release Notes Template

```md
## [x.y.z] - YYYY-MM-DD

- Add `Ratomic::Map#fetch_or_store` for Ractor-safe concurrent cache initialization.
- Add `Ratomic::Map#compute` for atomic per-key updates.
- Add `Ratomic::Map#increment` and `#decrement` for concurrent counters.
```
