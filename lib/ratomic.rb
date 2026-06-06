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

  class << self
    def native_extension_path
      ruby_api_ver = RbConfig::CONFIG.fetch("ruby_version").split(".", 3)[0, 2].join(".")
      "ratomic/#{ruby_api_ver}/ratomic"
    end
    private :native_extension_path

    def development_native_extension_path
      "ratomic/ratomic"
    end
    private :development_native_extension_path

    def load_native_extension_path(path)
      require_relative path
      true
    rescue LoadError
      false
    end
    private :load_native_extension_path

    def load_native_extension
      @native_enabled =
        load_native_extension_path(native_extension_path) ||
        load_native_extension_path(development_native_extension_path)
    end

    def native_enabled?
      @native_enabled == true
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
