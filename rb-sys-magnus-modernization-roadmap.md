# ratomic: rb-sys + magnus Modernization Roadmap

> ratomic currently uses a hand-rolled C bridge + cbindgen + staticlib architecture that
> predates modern rb-sys conventions. This makes cross-platform precompiled gems impossible
> — directly blocking Issue #3. This roadmap migrates to the rb-sys + magnus + cdylib stack
> per https://oxidize-rb.org/docs, eliminating the C bridge entirely and unlocking fat gem
> releases for 7 platforms with zero Rust required from end users. The final step targets
> Ruby 4.0 exclusively -- per alignment with Mike -- rewriting all Ractor usage from the
> deprecated 3.x API (`Ractor.yield`, `Ractor#take`) to the modern `Ractor::Port` model.

## Checklist

### Prerequisites
- [x] Read https://oxidize-rb.org/docs/getting-started through deployment
- [x] branch from current trunk
- [x] Verify `docker compose run ruby34` is green on current trunk before dropping Ruby 3.x

### PR 1 — RbSys::ExtensionTask
- [x] Add `rb_sys` to gemspec dependencies
- [x] Replace `Rake::ExtensionTask` with `RbSys::ExtensionTask` in Rakefile
- [x] Add `cross_compile = true` and `cross_platform` list
- [x] CI green

### PR 2 — rb_sys/mkmf
- [x] Replace `extconf.rb` content with `require "rb_sys/mkmf"` + `create_rust_makefile`
- [x] Verify `bundle exec rake compile` still works
- [x] CI green

### PR 3 — magnus + cdylib (the big one)
- [x] Create root `Cargo.toml` workspace
- [x] Move Rust source from `rs/src/` → `ext/ratomic/src/`
- [x] Update `ext/ratomic/Cargo.toml` — `crate-type = ["cdylib"]`
- [x] Add `magnus` dependency
- [x] Rewrite each module (counter, hashmap, mpmc_queue, pool) using magnus
- [x] Write `ext/ratomic/src/lib.rs` with `#[magnus::init]`
- [x] Delete `ext/ratomic/ratomic.c`
- [x] Delete `rs/rust-atomics.h`
- [x] Delete `Makefile` bindgen target
- [x] Remove `cbindgen` from `Dockerfile` and Rakefile
- [x] Update Rakefile default task — remove `rust`, `bindgen` steps
- [x] All 12 Ruby tests green
- [x] All Rust unit tests green
- [x] Docker build green

### PR 4 — Release workflow
- [x] Add `.github/actions/setup-ruby-rust/action.yml`
- [x] Update `test.yml` to use composite action
- [x] Add `release.yml` with full pipeline
- [ ] Configure Trusted Publisher on RubyGems.org (owner: mperham, repo: ratomic, workflow: release.yml, environment: release)
- [ ] Dry-run the workflow via `workflow_dispatch` — verify gem list correct
- [ ] Publish v0.2.0

### PR 5 — Ruby 4 migration
- [x] CI ruby matrix in `test.yml` set to `["4.0"]` only — drops Ruby 3.x per alignment with Mike
- [x] Bump `required_ruby_version` to `>= "4.0.0"` in gemspec
- [x] Update RuboCop `TargetRubyVersion: 4.0`
- [x] Rewrite `Pool` checkout/checkin using `Ractor::Port`
- [x] Replace `Ractor.yield` / `Ractor#take` in test suite
- [x] Replace `Ractor#close_incoming` / `close_outgoing` throughout
- [x] Add `Ractor#join` / `Ractor#value` where termination is awaited
- [x] All tests green on Ruby 4.0
---

## Notes

**On the `perf/` PR's `-Wl,--strip-all`:**
Once PR 2 lands, the manual linker flag in `extconf.rb` becomes redundant.
`rb_sys/mkmf` + `[profile.release]` in `Cargo.toml` handle stripping automatically.
The `panic = "abort"`, `lto = true`, `codegen-units = 1` settings remain valid and continue to apply.

**On `cbindgen`:**
Once PR 3 lands, `cbindgen` is no longer needed anywhere — no more C header, no more bindgen step.
Remove from `Dockerfile`, `Makefile`, and Rakefile.

**On Trusted Publishers:**
PR 4 uses `rubygems/release-gem@v1` with OIDC Trusted Publishing instead of a `RUBYGEMS_API_KEY` secret.
Requires one-time setup on RubyGems.org by the gem owner. No secrets to rotate, no credentials to leak.

**On Windows (`x64-mingw-ucrt`):**
Included in the cross-platform list because rb-sys-dock supports it. Not tested locally.
Let CI be the arbiter for Windows.

**On the `rs/` directory:**
Will be deleted entirely in PR 3. The Rust source moves to `ext/ratomic/src/`.
The `Makefile` in the root (which only served `make rust` and `make bindgen`) will be also deleted.
