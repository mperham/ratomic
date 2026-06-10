## [Unreleased]

## [0.4.0] - 2026-06-10

### Added

* Introduced `Ratomic::LocalPool`, a new pooling primitive for live resources that should remain local to the Ractor that created them.
* Added Redis-based smoke tests demonstrating safe operation across both Threads and Ractors.
* Added queue producer/consumer Redis examples.
* Added RBS definitions for `LocalPool`.
* Expanded API documentation and usage examples.

### Design

`Ratomic::Pool` and `Ratomic::LocalPool` serve different ownership models:

* `Pool` — ownership transfer
* `LocalPool` — ownership preservation

`LocalPool` is intended for resources such as:

* Redis clients
* Database connections
* HTTP clients
* Kafka producers
* Other stateful network resources

### Notes

`LocalPool` is implemented in pure Ruby and is not backed by Ratomic's Rust extension.


## [0.3.5] - 2026-06-06

- Fix the native loader so development loads the compiled extension from the
  workspace layout while installed gems still resolve the versioned packaged
  native path.
- Add loader coverage for the native-enabled path and keep the release smoke
  test validating the packaged native gem shape before publish.

## [0.3.4] - 2026-06-06

- Move the compiled native extension into the versioned `lib/ratomic/4.0/`
  layout used by the installed gem.
- Load the versioned native artifact explicitly and mark native support as
  unavailable when the extension is missing.
- Add loader coverage for both the versioned native path and the native-disabled
  branch.

## [0.3.3] - 2026-06-06

- Fix `require "ratomic"` for installed gems by resolving the packaged native
  extension layout directly.
- Add a release smoke test that installs the built gem artifact into a clean
  gem home before publishing.

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
