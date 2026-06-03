## [Unreleased]
- Add `length`, `size`, `peek` and `empty?` methods to Ratomic::Queue
- Change `Ratomic::Pool` to use Ruby 4 `Ractor::Port` ownership transfer semantics, fixing the unsafe stale-reference behavior reported in [#5](https://github.com/mperham/ratomic/issues/5)

## [0.1.0] - 2025-03-20

- Initial release
