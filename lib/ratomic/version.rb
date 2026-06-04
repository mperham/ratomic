# frozen_string_literal: true

# Ratomic provides Ractor-friendly mutable data structures backed by native
# Rust concurrency primitives.
#
# The public API currently includes {Counter}, {Map}, {Queue}, and {Pool}.
module Ratomic
  # Current gem version.
  VERSION = "0.2.1"
end
