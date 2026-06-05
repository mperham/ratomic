# frozen_string_literal: true

module Ratomic
  # A Ractor-shareable concurrent Hash backed by Rust's DashMap.
  #
  # Map gives Ruby code a small, Ruby-shaped API over DashMap's concurrent
  # storage. It is suitable for runtime state with shareable keys and values
  # that are safe to access from multiple Ractors, such as integer counters or
  # immutable offsets.
  #
  # This is not a full Hash replacement. Iteration and arbitrary mutable object
  # borrowing are intentionally absent.
  #
  # @example Store pipeline offsets
  #   OFFSETS = Ratomic::Map.new
  #   OFFSETS[:source_a] = 42
  #   OFFSETS[:source_a] # => 42
  #
  # @!method get(key)
  #   Read a value by +key+.
  #
  #   Missing keys return nil, so use #key? or #fetch when stored nil values
  #   need to be distinguished from missing entries.
  #
  #   @param key [Object] lookup key
  #   @return [Object, nil] the stored value, or nil when the key is missing
  #
  # @!method set(key, value)
  #   Set a value for +key+.
  #
  #   This is the method behind `#[]=` and follows Ruby setter semantics by
  #   returning the assigned value.
  #
  #   @param key [Object] key to write
  #   @param value [Object] value to store
  #   @return [Object] the assigned value
  #
  # @!method []=(key, value)
  #   Set a value for +key+.
  #
  #   In assignment form, Ruby returns the value assigned to the expression.
  #
  #   @param key [Object] key to write
  #   @param value [Object] value to store
  #   @return [Object] the assigned value
  #
  # @!method key?(key)
  #   Check whether +key+ currently exists in the map.
  #
  #   Unlike #get and #[], this distinguishes missing keys from stored nil
  #   values.
  #
  #   @param key [Object] lookup key
  #   @return [Boolean] true when the key currently exists
  #
  # @!method delete(key)
  #   Remove +key+ and return its previous value.
  #
  #   Missing keys return nil. Stored nil values also return nil; use #key?
  #   before deleting if that distinction matters.
  #
  #   @param key [Object] key to remove
  #   @return [Object, nil] the previous value, or nil when the key was missing
  #
  # @!method clear
  #   Remove all entries from the map.
  #
  #   @return [Ratomic::Map] self
  #
  # @!method size
  #   Return the current number of entries.
  #
  #   Since this is a concurrent map, the value is a moment-in-time observation.
  #
  #   @return [Integer] the current number of entries
  #
  # @!method fetch_and_modify(key)
  #   Replace the existing value for +key+ with the block return value.
  #
  #   TODO: Revisit this name once the Map API settles. Prefer public method
  #   names that stay as close as possible to Ruby Hash semantics.
  #
  #   The key must already exist. The operation is atomic for the key. The block
  #   runs while the map entry is locked, so avoid using this method for
  #   Ractor-hot loops or calling back into the same map from inside the block.
  #   If the block raises, the previous value is preserved.
  #
  #   @param key [Object] key to modify in place
  #   @yieldparam value [Object] the current stored value
  #   @return [void] nothing useful is returned
  #   @raise [LocalJumpError] if no block is given
  #   @raise [Exception] any exception raised by the block
  #
  # @!method compute(key)
  #   Atomically compute and store a value for +key+.
  #
  #   If +key+ exists, yields the current value. If +key+ is missing, yields
  #   nil. The block return value is stored and returned.
  #
  #   The operation is atomic for the key. The block runs while the map entry is
  #   locked, so avoid using this method for Ractor-hot loops or calling back
  #   into the same map from inside the block. Prefer native update helpers such
  #   as #increment when they fit the workflow.
  #
  #   If the block raises, the previous value is preserved. If the key was
  #   missing, no entry is inserted.
  #
  #   @param key [Object] key to compute
  #   @yieldparam value [Object, nil] the current stored value, or nil when missing
  #   @return [Object] the newly stored value
  #   @raise [LocalJumpError] if no block is given
  #   @raise [Exception] any exception raised by the block
  #
  # @!method fetch_or_store(key)
  #   Return the existing value for +key+, or atomically store the block result.
  #
  #   If +key+ exists, returns the current value and does not yield. If +key+
  #   is missing, yields once, stores the block return value, and returns it.
  #
  #   The operation is atomic for the key. Under contention, only one stored
  #   value wins for a missing key. The block runs while the map entry is locked,
  #   so avoid using this method for Ractor-hot loops or calling back into the
  #   same map from inside the block.
  #
  #   If the block raises, no entry is inserted.
  #
  #   @param key [Object] key to read or initialize
  #   @return [Object] the existing or newly stored value
  #   @raise [LocalJumpError] if no block is given
  #   @raise [Exception] any exception raised by the block
  #
  # @!method upsert(key, initial)
  #   Atomically insert +initial+ for a missing key, or update an existing value.
  #
  #   If +key+ is missing, stores and returns +initial+ without yielding. If
  #   +key+ exists, yields the current value, stores the block return value, and
  #   returns it.
  #
  #   The operation is atomic for the key. The block runs while the map entry is
  #   locked, so avoid using this method for Ractor-hot loops or calling back
  #   into the same map from inside the block. Prefer native update helpers such
  #   as #increment when they fit the workflow.
  #
  #   If the block raises, the previous value is preserved.
  #
  #   @param key [Object] key to update
  #   @param initial [Object] value to use when the key is missing
  #   @yieldparam value [Object, nil] the current stored value, or nil when missing
  #   @return [Object] the inserted or newly stored value
  #   @raise [LocalJumpError] if no block is given
  #   @raise [Exception] any exception raised by the block
  #
  # @!method increment(key, by = 1)
  #   Atomically increment the numeric value for +key+.
  #
  #   Missing keys start at zero. Existing non-numeric values raise TypeError
  #   and are left unchanged. This uses a native update path and is the preferred
  #   counter primitive for Ractor-heavy workloads.
  #
  #   @param key [Object] counter key to increment
  #   @param by [Numeric] amount to add
  #   @return [Numeric] the newly stored value
  #   @raise [TypeError] if +by+ or the existing value is not numeric
  #
  # @!method decrement(key, by = 1)
  #   Atomically decrement the numeric value for +key+.
  #
  #   Missing keys start at zero.
  #
  #   @param key [Object] counter key to decrement
  #   @param by [Numeric] amount to subtract
  #   @return [Numeric] the newly stored value
  #   @raise [TypeError] if +by+ or the existing value is not numeric
  #
  # @!method append(key, value)
  #   Atomically append +value+ to an Array bucket for +key+.
  #
  #   The stored Array is replaced rather than mutated in place.
  #
  #   @param key [Object] bucket key to append into
  #   @param value [Object] value to append
  #   @return [Array] the newly stored frozen Array
  #   @raise [TypeError] if the existing value is not an Array
  #
  # @!method add_to_set(key, value)
  #   Atomically add +value+ to a Set bucket for +key+.
  #
  #   The stored Set is replaced rather than mutated in place.
  #
  #   @param key [Object] bucket key to update
  #   @param value [Object] value to add to the set
  #   @return [Set] the newly stored frozen Set
  #   @raise [TypeError] if the existing value is not a Set
  class Map
    # Set a value for +key+.
    #
    # In assignment form, Ruby returns the assigned value.
    #
    # @param key [Object] key to write
    # @param value [Object] value to store
    # @return [Object] the assigned value
    def []=(key, value)
      set(key, value)
    end

    # Read a value by +key+.
    #
    # Missing keys currently return nil, so storing nil is ambiguous.
    #
    # @param key [Object] lookup key
    # @return [Object, nil] the stored value, or nil when the key is missing
    def [](key)
      get(key)
    end

    # Fetch a value by +key+.
    #
    # Unlike #[], this distinguishes missing keys from explicit nil values.
    #
    # @param key [Object] lookup key
    # @param default [Object] fallback value to return when the key is missing
    # @yieldparam key [Object] the missing key
    # @return [Object] the found value, default, or block result
    # @raise [KeyError] if +key+ is missing and no default or block is provided
    def fetch(key, default = UNDEFINED)
      return get(key) if key?(key)
      return yield key if block_given?
      return default unless default.equal?(UNDEFINED)

      raise KeyError, "key not found: #{key.inspect}"
    end

    # Atomically increment the numeric value for +key+.
    #
    # Missing keys start at zero. Existing non-numeric values raise TypeError
    # and are left unchanged. This uses a native update path and is the preferred
    # counter primitive for Ractor-heavy workloads.
    #
    # @param key [Object] counter key to increment
    # @param by [Numeric] amount to add
    # @return [Numeric] the newly stored value
    # @raise [TypeError] if +by+ or the existing value is not numeric
    def increment(key, by = 1)
      raise TypeError, "amount must be numeric: #{by.inspect}" unless by.is_a?(Numeric)

      __increment_numeric(key, by)
    end

    # Atomically decrement the numeric value for +key+.
    #
    # Missing keys start at zero.
    #
    # @param key [Object] counter key to decrement
    # @param by [Numeric] amount to subtract
    # @return [Numeric] the newly stored value
    # @raise [TypeError] if +by+ or the existing value is not numeric
    def decrement(key, by = 1)
      raise TypeError, "amount must be numeric: #{by.inspect}" unless by.is_a?(Numeric)

      increment(key, -by)
    end

    # Atomically append +value+ to an Array bucket for +key+.
    #
    # The stored Array is replaced rather than mutated in place.
    #
    # @param key [Object] bucket key to append into
    # @param value [Object] value to append
    # @return [Array] the newly stored frozen Array
    # @raise [TypeError] if the existing value is not an Array
    def append(key, value)
      missing = !key?(key)
      compute(key) do |old_value|
        if old_value.nil? && missing
          [value].freeze
        else
          unless old_value.is_a?(Array)
            raise TypeError,
                  "existing value for #{key.inspect} must be an Array: #{old_value.inspect}"
          end

          (old_value + [value]).freeze
        end
      end
    end

    # Atomically add +value+ to a Set bucket for +key+.
    #
    # The stored Set is replaced rather than mutated in place.
    #
    # @param key [Object] bucket key to update
    # @param value [Object] value to add to the set
    # @return [Set] the newly stored frozen Set
    # @raise [TypeError] if the existing value is not a Set
    def add_to_set(key, value)
      missing = !key?(key)
      compute(key) do |old_value|
        if old_value.nil? && missing
          Set[value].freeze
        else
          unless old_value.is_a?(Set)
            raise TypeError,
                  "existing value for #{key.inspect} must be a Set: #{old_value.inspect}"
          end

          (old_value | [value]).freeze
        end
      end
    end

    # Alias for #size.
    #
    # @return [Integer] the current number of entries
    def length
      size
    end

    # Check whether the map currently has no entries.
    #
    # @return [Boolean] true when the map currently has no entries
    def empty?
      size.zero?
    end

    # Alias for #key?.
    #
    # @param key [Object] lookup key
    # @return [Boolean] true when the key currently exists
    def include?(key)
      key?(key)
    end
    alias member? include?
  end
end
