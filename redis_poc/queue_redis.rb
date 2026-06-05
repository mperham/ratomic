# Run with `bundle exec ruby app.rb`
require 'ratomic'
require 'redis-client'
# require 'json'
# require 'securerandom'

REDIS_HOST = Ractor.make_shareable(ENV.fetch("REDIS_HOST", "127.0.0.1").dup.freeze)

times = 20_000
queues = %w(one two three four five)
COUNTS = Ratomic::Map.new
POOL = Ratomic::Pool.new(50, 1) { RedisClient.new(host: REDIS_HOST, read_timeout: 3) }

def concurrent_value(worker)
  worker.join if worker.respond_to?(:join)
  worker.value
end

POOL.with {|c| c.call("flushdb") }
POOL.with do |conn|
  queues.each do |q|
    COUNTS.set(q, Ratomic::Counter.new)
  end
end

# TYPE=Thread or TYPE=Ractor bundle exec ruby queue_redis.rb
conctype = Object.const_get(ENV.fetch("TYPE", "Ractor"))

p [:start, Time.now]
concurrency = []
2.times do |off|
  concurrency << conctype.new(off, queues, times) do |ridx, qs, cnt|
    p [:client, Time.now]
    # offset = (ridx * cnt)
    qsz = qs.size
    POOL.with {|c|
      cnt.times do |idx|
        q = qs[idx % qsz]
        # jid = SecureRandom.hex(12)
        c.call("lpush", q, "job")
          # m.call("sadd", "jids", jid)
        COUNTS.get(q).increment(1)
      end
    }
    p [:client_done, Time.now]
  end
end

5.times do
  concurrency << conctype.new(queues) do |q|
    p [:process, q, Time.now]
    loop do
      element = POOL.with do |conn|
        conn.call("brpop", *q, 2)
      end
      p element unless element.nil? || element.size == 2
      break unless element&.size == 2
      # COUNTS.get(q).decrement(1)
      # job = JSON.parse(element[1])
      # POOL.with {|c| c.call("srem", "jids", job['jid']) }
      # job
    end
  ensure
    p [:process_done, q, Time.now]
  end
end

Thread.new do
  loop do
    p(queues.map do |q|
      { q => COUNTS.get(q).read }
    end)
    sleep 2
  end
end

concurrency.map { |worker| concurrent_value(worker) }
p [:end, Time.now]

# p POOL.with {|c| c.call "scard", "jids" }
