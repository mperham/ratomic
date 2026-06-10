# Run with `TYPE=Thread bundle exec ruby redis/queue_redis.rb`
# Run with `TYPE=Ractor bundle exec ruby redis/queue_redis.rb`
require "ratomic"
require "redis-client"

RedisClientFactory = Data.define(:host, :read_timeout) do
  def call
    RedisClient.new(host: host, read_timeout: read_timeout)
  end
end

REDIS_HOST = Ractor.make_shareable(ENV.fetch("REDIS_HOST", "127.0.0.1").dup.freeze)
TIMES = Integer(ENV.fetch("TIMES", "20000"))
PRODUCERS = Integer(ENV.fetch("PRODUCERS", "2"))
CONSUMERS = Integer(ENV.fetch("CONSUMERS", "5"))
STOP = Ractor.make_shareable("__ratomic_stop__".freeze)

QUEUES = Ractor.make_shareable(%w[one two three four five].map(&:freeze).freeze)
COUNTS = Ratomic::Map.new
POOL = Ratomic::LocalPool.new(
  size: Integer(ENV.fetch("POOL_SIZE", "8")),
  timeout: Float(ENV.fetch("POOL_TIMEOUT", "1")),
  factory: RedisClientFactory.new(REDIS_HOST, 3)
)

def concurrent_value(worker)
  worker.join if worker.respond_to?(:join)
  worker.value
end

POOL.with { |client| client.call("flushdb") }
QUEUES.each { |queue| COUNTS.set(queue, Ratomic::Counter.new) }

# TYPE=Thread or TYPE=Ractor bundle exec ruby queue_redis.rb
concurrency_type = Object.const_get(ENV.fetch("TYPE", "Ractor"))

p [:start, concurrency_type, Time.now]

producers = PRODUCERS.times.map do |producer_index|
  concurrency_type.new(producer_index, QUEUES, TIMES) do |ridx, queues, count|
    queue_count = queues.size

    count.times do |idx|
      queue = queues[(idx + ridx) % queue_count]
      POOL.with { |client| client.call("lpush", queue, "job") }
      COUNTS.get(queue).increment(1)
    end

    [:producer_done, ridx]
  end
end

consumers = CONSUMERS.times.map do |consumer_index|
  concurrency_type.new(consumer_index, QUEUES, STOP) do |ridx, queues, stop_marker|
    processed = 0

    loop do
      item = POOL.with { |client| client.call("brpop", *queues, 2) }
      next if item.nil?

      queue, payload = item
      break if payload == stop_marker

      COUNTS.get(queue).decrement(1)
      processed += 1
    end

    [:consumer_done, ridx, processed]
  end
end

producer_results = producers.map { |worker| concurrent_value(worker) }

CONSUMERS.times do
  POOL.with { |client| client.call("lpush", QUEUES.first, STOP) }
end

consumer_results = consumers.map { |worker| concurrent_value(worker) }

p producer_results
p consumer_results
p(QUEUES.map { |queue| { queue => COUNTS.get(queue).read } })
p [:end, Time.now]
