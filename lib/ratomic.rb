# frozen_string_literal: true

require_relative "ratomic/version"
require_relative "ratomic/ratomic"

module Ratomic
  class Error < StandardError; end

  class Counter
    # def increment
    # def read
  end

  class Undefined
    def inspect
      "#<Undefined>"
    end
  end
  UNDEFINED = Ractor.make_shareable(Undefined.new)

  class FixedSizeObjectPool
    def with
      obj_and_idx = checkout
      if obj_and_idx.nil?
        raise Ratomic::Error, "pool checkout timeout"
      else
        yield obj_and_idx[0]
      end
    ensure
      unless obj_and_idx.nil?
        checkin(obj_and_idx[1])
      end
    end
  end

  class ConcurrentHashMap
    def self.with_keys(known_keys)
      map = new
      known_keys.each { |key| map.set(key, 0) }
      map
    end

    def increment(key)
      fetch_and_modify(key) { |v| v + 1 }
    end

    def sum(known_keys)
      known_keys.map { |k| get(k) }.sum
    end
  end

end
