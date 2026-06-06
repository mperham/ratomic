# frozen_string_literal: true

require "rbconfig"

# Ratomic provides mutable data structures for Ruby Ractors. Its primitives
# are backed by native Rust concurrency libraries so Ruby code can share useful
# state across Ractors without falling back to one global lock. Pool uses Ruby
# Ractor ownership-transfer primitives instead of the native Rust path.
#
# The public API currently includes {Counter}, {Map}, {Queue}, and {Pool}.
module Ratomic
  def self.load_native_extension
    ruby_api_ver = RbConfig::CONFIG.fetch("ruby_version").split(".", 3)[0, 2].join(".")
    require_relative "ratomic/#{ruby_api_ver}/ratomic"
    @native_enabled = true
  rescue LoadError
    @native_enabled = false
  end

  def self.native_enabled?
    @native_enabled == true
  end
  private_class_method :load_native_extension

  # Base error class for Ratomic-specific failures.
  class Error < StandardError; end
end

Ratomic.send(:load_native_extension)
require_relative "ratomic/version"
require_relative "ratomic/undefined"
require_relative "ratomic/counter"
require_relative "ratomic/map"
require_relative "ratomic/queue"
require_relative "ratomic/pool"
