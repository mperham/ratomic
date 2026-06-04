# frozen_string_literal: true

module Ratomic
  # Ruby convenience methods for {Queue}.
  module QueueMethods
    # Push an item and return the queue for chaining.
    #
    # @param item [Object]
    # @return [Ratomic::Queue]
    def <<(item)
      push(item)
      self
    end
  end

  # A Ractor-shareable multi-producer, multi-consumer queue.
  #
  # Queue stores Ruby objects in a fixed-size native ring buffer. Push blocks
  # when the queue is full; pop blocks when the queue is empty.
  #
  # @example Push and pop work
  #   queue = Ratomic::Queue.new(128)
  #   queue << "job"
  #   queue.pop # => "job"
  #
  # @!method self.new(capacity)
  #   Create a queue with a fixed capacity.
  #
  #   @param capacity [Integer]
  #   @return [Ratomic::Queue]
  #   @raise [ArgumentError] if capacity is outside the supported range
  #   @raise [TypeError] if capacity is not an Integer
  #
  # @!method push(item)
  #   Push an item, blocking until space is available.
  #
  #   @param item [Object]
  #   @return [void]
  #
  # @!method pop
  #   Pop an item, blocking until one is available.
  #
  #   @return [Object]
  #
  # @!method peek
  #   Return the next item without removing it.
  #
  #   Since this is a concurrent queue, the value is a moment-in-time
  #   observation.
  #
  #   @return [Object, nil]
  #
  # @!method empty?
  #   Check whether the queue currently appears empty.
  #
  #   Since this is a concurrent queue, the value is a moment-in-time
  #   observation.
  #
  #   @return [Boolean]
  #
  # @!method size
  #   Return the current queue size.
  #
  #   Since this is a concurrent queue, the value is a moment-in-time
  #   observation.
  #
  #   @return [Integer]
  #
  # @!method length
  #   Alias for #size.
  #
  #   @return [Integer]
  class Queue
    prepend QueueMethods
  end
end
