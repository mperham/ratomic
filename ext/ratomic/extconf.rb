# frozen_string_literal: true

require "mkmf"

# Makes all symbols private by default to avoid unintended conflict
# with other gems. To explicitly export symbols you can use RUBY_FUNC_EXPORTED
# selectively, or entirely remove this flag.
append_cflags("-fvisibility=hidden")

# Strip debug symbols from the final .so in release builds
append_ldflags("-Wl,--strip-all") unless ENV["DEBUG"]

rust_atomics_path = File.expand_path("../../../rs", __FILE__)
# rubocop:disable Style/GlobalVars
$INCFLAGS << " -I#{rust_atomics_path}"
$LDFLAGS << " -L#{rust_atomics_path}/target/release -lrust_atomics"
# rubocop:enable Style/GlobalVars

create_makefile("ratomic/ratomic")
