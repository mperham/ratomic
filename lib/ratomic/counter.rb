# frozen_string_literal: true

module Ratomic
  # Ruby convenience methods for {Counter}.
  module CounterMethods
    # Read the current counter value.
    #
    # @return [Integer]
    def value
      read
    end

    # Coerce the counter to an Integer snapshot.
    #
    # @return [Integer]
    def to_i
      read
    end

    # Check whether the current counter value is zero.
    #
    # @return [Boolean]
    def zero?
      read.zero?
    end

    # Increment the counter.
    #
    # @param amt [Integer] amount to add
    # @raise [ArgumentError] if +amt+ is negative
    # @return [void]
    def inc(amt = 1)
      raise ArgumentError, "amount must be positive: #{amt}" if amt.negative?

      increment(amt)
    end

    # Decrement the counter.
    #
    # @param amt [Integer] amount to subtract
    # @raise [ArgumentError] if +amt+ is negative
    # @return [void]
    def dec(amt = 1)
      raise ArgumentError, "amount must be positive: #{amt}" if amt.negative?

      decrement(amt)
    end
  end

  # A Ractor-shareable atomic counter.
  #
  # Counter stores an unsigned integer in native Rust atomics and can be shared
  # safely across Ractors.
  #
  # @example Count work across Ractors
  #   counter = Ratomic::Counter.new
  #   counter.inc
  #   counter.read # => 1
  #
  # @!method self.new
  #   Create a counter initialized to zero.
  #
  #   @return [Ratomic::Counter]
  #
  # @!method read
  #   Read the current counter value.
  #
  #   @return [Integer]
  #
  # @!method increment(amt)
  #   Increment the counter by +amt+.
  #
  #   @param amt [Integer]
  #   @return [void]
  #
  # @!method decrement(amt)
  #   Decrement the counter by +amt+.
  #
  #   @param amt [Integer]
  #   @return [void]
  class Counter
    prepend CounterMethods
  end
end
