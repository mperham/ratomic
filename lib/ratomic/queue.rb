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

  Queue.prepend(QueueMethods)
end
