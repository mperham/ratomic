# frozen_string_literal: true

module Ratomic
  # A Ractor-shareable atomic counter.
  #
  # Counter stores an unsigned integer in native Rust atomics and can be shared
  # safely across Ractors.
  #
  # @example Count work across Ractors
  #   counter = Ratomic::Counter.new
  #   counter.increment(1) # => 1
  #   counter.read # => 1
  #
  # @!method self.new
  #   Create a counter initialized to zero.
  #
  #   @return [Ratomic::Counter] a new shareable counter
  #
  # @!method read
  #   Read the current counter value.
  #
  #   @return [Integer] the current counter value
  #
  # @!method increment(amt)
  #   Increment the counter by +amt+.
  #
  #   @param amt [Integer] amount to add to the counter
  #   @return [Integer] the updated counter value
  #
  # @!method decrement(amt)
  #   Decrement the counter by +amt+.
  #
  #   @param amt [Integer] amount to subtract from the counter
  #   @return [Integer] the updated counter value
  class Counter
    # Read the current counter value.
    #
    # @return [Integer] the current counter value
    def value
      read
    end

    # Coerce the counter to an Integer snapshot.
    #
    # @return [Integer] the current counter value
    def to_i
      read
    end

    # Check whether the current counter value is zero.
    #
    # @return [Boolean] true when the counter currently reads zero
    def zero?
      read.zero?
    end
  end
end
