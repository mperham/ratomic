# frozen_string_literal: true

module Ratomic
  # A Ractor-shareable concurrent map.
  #
  # Map is a public alias for the native ConcurrentHashMap class. It is suitable
  # for runtime state with shareable keys and values that are safe to access
  # from multiple Ractors, such as counters or immutable offsets.
  #
  # This is not a full Hash replacement. Iteration and arbitrary mutable object
  # borrowing are intentionally absent.
  #
  # @example Store pipeline offsets
  #   OFFSETS = Ratomic::Map.new
  #   OFFSETS[:source_a] = 42
  #   OFFSETS[:source_a] # => 42
  Map = ConcurrentHashMap

  # Ruby convenience methods for {Map}.
  module MapMethods
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
  end

  ConcurrentHashMap.prepend(MapMethods)
end
