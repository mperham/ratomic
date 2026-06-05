# frozen_string_literal: true

# Ratomic provides mutable data structures for Ruby Ractors. Its primitives
# are backed by native Rust concurrency libraries so Ruby code can share useful
# state across Ractors without falling back to one global lock. Pool uses Ruby
# Ractor ownership-transfer primitives instead of the native Rust path.
#
# The public API currently includes {Counter}, {Map}, {Queue}, and {Pool}.
module Ratomic
  # Base error class for Ratomic-specific failures.
  class Error < StandardError; end
end

require "ratomic/ratomic"
require "ratomic/version"

require "ratomic/undefined"
require "ratomic/counter"
require "ratomic/map"
require "ratomic/queue"
require "ratomic/pool"
