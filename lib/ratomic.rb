# frozen_string_literal: true

require "rbconfig"

# Ratomic provides mutable data structures for Ruby Ractors. Its primitives
# are backed by native Rust concurrency libraries so Ruby code can share useful
# state across Ractors without falling back to one global lock. Pool uses Ruby
# Ractor ownership-transfer primitives instead of the native Rust path.
#
# The public API currently includes {Counter}, {Map}, {Queue}, and {Pool}.
module Ratomic
  # Base error class for Ratomic-specific failures.
  class Error < StandardError; end

  def self.load_native_extension
    packaged_native = Dir[File.join(__dir__, "ratomic", "*", "ratomic.{so,bundle}")].min

    if packaged_native
      require packaged_native.sub(/\.(so|bundle)\z/, "")
    else
      require "ratomic/ratomic"
    end
  end
  private_class_method :load_native_extension
end

Ratomic.send(:load_native_extension)
require "ratomic/version"

require "ratomic/undefined"
require "ratomic/counter"
require "ratomic/map"
require "ratomic/queue"
require "ratomic/pool"
