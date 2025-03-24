# Run with `bundle exec ruby app.rb`
require 'ratomic'
require 'redis-client'
# require 'json'
# require 'securerandom'

times = 20_000
queues = %w(one two three four five)
COUNTS = Ratomic::Map.new
POOL = Ratomic::Pool.new(50, 1) { RedisClient.new(read_timeout: 3) }

class Ractor
  # create same API as Thread
  alias_method :value, :take
end

POOL.with {|c| c.call("flushdb") }
POOL.with do |conn|
  queues.each do |q|
    COUNTS.set(q, Ratomic::Counter.new)
  end
end

# TYPE=Thread or TYPE=Ractor bundle exec ...
conctype = Object.const_get(ENV["type"] || "Ractor")

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
        COUNTS.get(q).inc
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
      p element unless element&.size == 2
      break unless element&.size == 2
      # COUNTS.get(q).dec
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

concurrency.map(&:value)
p [:end, Time.now]

# p POOL.with {|c| c.call "scard", "jids" }

