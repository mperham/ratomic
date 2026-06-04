# frozen_string_literal: true

module Ratomic
  # A Ractor-shareable concurrent Hash backed by Rust's DashMap.
  #
  # Map gives Ruby code a small, Ruby-shaped API over DashMap's concurrent
  # storage. It is suitable for runtime state with shareable keys and values
  # that are safe to access from multiple Ractors, such as counters or immutable
  # offsets.
  #
  # This is not a full Hash replacement. Iteration and arbitrary mutable object
  # borrowing are intentionally absent.
  #
  # @example Store pipeline offsets
  #   OFFSETS = Ratomic::Map.new
  #   OFFSETS[:source_a] = 42
  #   OFFSETS[:source_a] # => 42
  class Map
    # Set a value for +key+.
    #
    # @param key [Object]
    # @param value [Object]
    # @return [void]
    def []=(key, value)
      set(key, value)
    end

    # Read a value by +key+.
    #
    # Missing keys currently return nil, so storing nil is ambiguous.
    #
    # @param key [Object]
    # @return [Object, nil]
    def [](key)
      get(key)
    end

    # Fetch a value by +key+.
    #
    # Unlike #[], this distinguishes missing keys from explicit nil values.
    #
    # @param key [Object]
    # @param default [Object]
    # @yieldparam key [Object]
    # @return [Object]
    # @raise [KeyError] if +key+ is missing and no default or block is provided
    def fetch(key, default = UNDEFINED)
      return get(key) if key?(key)
      return yield key if block_given?
      return default unless default.equal?(UNDEFINED)

      raise KeyError, "key not found: #{key.inspect}"
    end

    # Alias for #size.
    #
    # @return [Integer]
    def length
      size
    end

    # Check whether the map currently has no entries.
    #
    # @return [Boolean]
    def empty?
      size.zero?
    end

    # Alias for #key?.
    #
    # @param key [Object]
    # @return [Boolean]
    def include?(key)
      key?(key)
    end
    alias member? include?
  end
end
