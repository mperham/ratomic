# Run with `bundle exec ruby app.rb`
require 'ratomic'
require 'redis-client'

queues = %w(one two three four five)
COUNTS = Ratomic::Map.new
POOL = Ratomic::Pool.new(50, 1) { RedisClient.new }

class Ractor
  # create same API as Thread
  alias_method :value, :take
end

types = [Thread, Ractor]
types.each do |klass|
  POOL.with {|c| c.call("flushdb") }
  POOL.with do |conn|
    queues.each do |q|
      COUNTS.set(q, Ratomic::Counter.new)
      conn.call("lpush", q, "element")
    end
  end

  ending = Time.now + 10
  concurrency = []
  5.times do
    concurrency << klass.new(queues, ending) do |queues, stop|
      loop do
        q = queues.sample
        POOL.with do |conn|
          conn.call("rpoplpush", q, queues.sample)
          COUNTS.get(q).inc
        end
        # p [Time.now, stop]
        break if Time.now > stop
      end
    end
  end
  concurrency.map(&:value)
  p(klass, queues.map do |q|
    { q => COUNTS.get(q).read }
  end)
end

