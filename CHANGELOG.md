## [Unreleased]

## [0.3.2] - 2026-06-06

- Fix `require "ratomic"` for installed gems by resolving the versioned native
  extension layout.
- Add a regression test for the packaged gem loader path.
- Keep the curated RBS signatures packaged with the gem.

## [0.3.1] - 2026-06-05

- Realign `Counter`, `Map`, and `Queue` return semantics with Ruby conventions.
- Expand YARD comments across the public API to keep full documentation coverage.
- Move the top-level module docs to the gem entrypoint for a cleaner load path.

## [0.3.0] - 2026-06-05

- Promote the DashMap-backed `Ratomic::Map` API as the primary concurrent Hash primitive.
- Add `Ratomic::Map#key?`, `#include?`, `#member?`, and `#delete`.
- Add `Ratomic::Map#fetch`, `#compute`, `#fetch_or_store`, and `#upsert` for atomic per-key workflows.
- Add `Ratomic::Map#increment`, `#decrement`, `#append`, and `#add_to_set` convenience methods for shared counters and bucket-style values.
- Improve API documentation for `Counter`, `Map`, `Queue`, and `Pool`.
- Add GitHub Pages deployment for generated YARD API documentation.
- Add Redis POC scripts for exercising `Ratomic::Map`, `Ratomic::Counter`, and `Ratomic::Pool` under Thread and Ractor workloads.
- Remove `Counter#inc` and `Counter#dec` in favor of the native `#increment` and `#decrement` methods.

## [0.2.1] - 2026-06-04

- Fix `Ratomic::Queue` slot indexing for non-power-of-two capacities.
- Fix `Ratomic::Map#fetch_and_modify` to propagate block exceptions instead of panicking.

## [0.2.0] - 2026-06-04

- Drop Ruby 3.x support and require Ruby 4.
- Add `length`, `size`, `peek`, and `empty?` methods to `Ratomic::Queue`.
- Change `Ratomic::Pool` to use Ruby 4 `Ractor::Port` ownership transfer semantics, fixing the unsafe stale-reference behavior reported in [#5]
(https://github.com/mperham/ratomic/issues/5).
- Organize Ruby wrapper code by primitive.
- Add primitive contract tests for `Counter`, `Map`, `Queue`, and `Pool`.
- Add SimpleCov coverage reporting.
- Undefine native typed-data default allocators to remove Ruby 4 warnings.

## [0.1.0] - 2025-03-20

- Initial release
