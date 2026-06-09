# Run with `bundle exec ruby basic_redis.rb`
require "ratomic"
require "redis-client"

RedisClientFactory = Data.define(:host) do
  def call
    RedisClient.new(host: host)
  end
end

REDIS_HOST = Ractor.make_shareable(ENV.fetch("REDIS_HOST", "127.0.0.1").dup.freeze)
QUEUES = Ractor.make_shareable(%w[one two three four five].map(&:freeze).freeze)
COUNTS = Ratomic::Map.new
POOL = Ratomic::LocalPool.new(
  size: Integer(ENV.fetch("POOL_SIZE", "10")),
  timeout: Float(ENV.fetch("POOL_TIMEOUT", "1")),
  factory: RedisClientFactory.new(REDIS_HOST)
)

def concurrent_value(worker)
  worker.join if worker.respond_to?(:join)
  worker.value
end

[Thread, Ractor].each do |klass|
  POOL.with { |client| client.call("flushdb") }
  QUEUES.each do |queue|
    COUNTS.set(queue, Ratomic::Counter.new)
    POOL.with { |client| client.call("lpush", queue, "element") }
  end

  ending = Time.now + Integer(ENV.fetch("SECONDS", "10"))
  workers = 5.times.map do
    klass.new(QUEUES, ending) do |queues, stop|
      loop do
        queue = queues.sample
        POOL.with do |client|
          client.call("rpoplpush", queue, queues.sample)
          COUNTS.get(queue).increment(1)
        end
        break if Time.now > stop
      end
    end
  end

  workers.each { |worker| concurrent_value(worker) }
  p(klass, QUEUES.map { |queue| { queue => COUNTS.get(queue).read } })
end
