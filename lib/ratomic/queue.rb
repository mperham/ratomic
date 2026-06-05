# frozen_string_literal: true

module Ratomic
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
  #   @param capacity [Integer] maximum number of items the queue can hold
  #   @return [Ratomic::Queue] a new shareable queue
  #   @raise [ArgumentError] if +capacity+ is outside the supported range
  #   @raise [TypeError] if +capacity+ cannot be converted to an Integer
  #
  # @!method push(item)
  #   Push an item, blocking until space is available.
  #
  #   @param item [Object] the item to append to the queue
  #   @return [Ratomic::Queue] self
  #
  # @!method pop
  #   Pop an item, blocking until one is available.
  #
  #   @return [Object] the next queued item
  #
  # @!method peek
  #   Return the next item without removing it.
  #
  #   Since this is a concurrent queue, the value is a moment-in-time
  #   observation.
  #
  #   @return [Object, nil] the next item, or nil if the queue is empty
  #
  # @!method empty?
  #   Check whether the queue currently appears empty.
  #
  #   Since this is a concurrent queue, the value is a moment-in-time
  #   observation.
  #
  #   @return [Boolean] true when the queue currently has no items
  #
  # @!method size
  #   Return the current queue size.
  #
  #   Since this is a concurrent queue, the value is a moment-in-time
  #   observation.
  #
  #   @return [Integer] the current number of queued items
  #
  # @!method length
  #   Alias for #size.
  #
  #   @return [Integer] the current number of queued items
  class Queue
    # Push an item and return the queue for chaining.
    #
    # @param item [Object] the item to append to the queue
    # @return [Ratomic::Queue] self
    def <<(item)
      push(item)
      self
    end
  end
end
