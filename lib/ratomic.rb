# frozen_string_literal: true

require_relative "ratomic/version"
require_relative "ratomic/ratomic"

module Ratomic
  class Error < StandardError; end

  ##
  # An atomic counter which can be incremented and decremented
  # safely by multiple Ractors concurrently.
  class Counter
    def value
      read
    end

    def inc(amt = 1)
      raise ArgumentError, "amount must be positive: #{amt}" if amt.negative?

      increment(amt)
    end

    def dec(amt = 1)
      raise ArgumentError, "amount must be positive: #{amt}" if amt.negative?

      decrement(amt)
    end
  end

  class Undefined
    def inspect
      "#<Undefined>"
    end
  end
  UNDEFINED = Ractor.make_shareable(Undefined.new)

  class Pool < FixedSizeObjectPool
    def initialize(size = 5, timeout = 1.0)
      super(size, (timeout * 1000).to_i)
    end

    def with
      obj_and_idx = checkout
      raise Ratomic::Error, "pool checkout timeout" if obj_and_idx.nil?

      yield obj_and_idx[0]
    ensure
      checkin(obj_and_idx[1]) unless obj_and_idx.nil?
    end
  end

  class Map < ConcurrentHashMap
    def []=(key, value)
      set(key, value)
    end

    def [](key)
      get(key)
    end

    # TODO: add as much of the Hash API as possible.
    # Stretch goal? Support Enumerable if DashMap can safely
    # iterate.
  end
end
