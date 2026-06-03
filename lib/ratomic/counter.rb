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

  Counter.prepend(CounterMethods)
end
