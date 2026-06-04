## [Unreleased]

- Add `Ratomic::Map#key?`, `#include?`, `#member?`, and `#delete`.

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
