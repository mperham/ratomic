# Run with `TYPE=Thread bundle exec ruby postgres/queue_postgres.rb`
# Run with `TYPE=Ractor bundle exec ruby postgres/queue_postgres.rb`
require "ratomic"
require "pg"

PostgresFactory = Data.define(:database_url) do
  def call
    PG.connect(database_url)
  end
end

DATABASE_URL = Ractor.make_shareable(ENV.fetch("DATABASE_URL", "postgresql://ratomic:ratomic@localhost:5432/ratomic_smoke").dup.freeze)
TIMES = Integer(ENV.fetch("TIMES", "20000"))
PRODUCERS = Integer(ENV.fetch("PRODUCERS", "2"))
CONSUMERS = Integer(ENV.fetch("CONSUMERS", "5"))
QUEUES = Ractor.make_shareable(%w[one two three four five].map(&:freeze).freeze)

POOL = Ratomic::LocalPool.new(
  size: Integer(ENV.fetch("POOL_SIZE", "8")),
  timeout: Float(ENV.fetch("POOL_TIMEOUT", "1")),
  factory: PostgresFactory.new(DATABASE_URL)
)

def concurrent_value(worker)
  worker.join if worker.respond_to?(:join)
  worker.value
end

def setup_database
  POOL.with do |conn|
    conn.exec(<<~SQL)
      CREATE TABLE IF NOT EXISTS ratomic_smoke_jobs (
        id bigserial PRIMARY KEY,
        queue_name text NOT NULL,
        payload text NOT NULL,
        processed boolean NOT NULL DEFAULT false,
        consumer_id integer
      )
    SQL
    conn.exec("TRUNCATE ratomic_smoke_jobs RESTART IDENTITY")
  end
end

def unprocessed_counts
  POOL.with do |conn|
    result = conn.exec(<<~SQL)
      SELECT queue_name, count(*)::integer AS count
      FROM ratomic_smoke_jobs
      WHERE processed = false
      GROUP BY queue_name
      ORDER BY queue_name
    SQL

    by_queue = result.each_with_object({}) do |row, counts|
      counts[row.fetch("queue_name")] = Integer(row.fetch("count"))
    end

    QUEUES.map { |queue| { queue => by_queue.fetch(queue, 0) } }
  end
end

setup_database
concurrency_type = Object.const_get(ENV.fetch("TYPE", "Ractor"))

p [:start, concurrency_type, Time.now]

producers = PRODUCERS.times.map do |producer_index|
  concurrency_type.new(producer_index, QUEUES, TIMES) do |ridx, queues, count|
    queue_count = queues.size

    count.times do |idx|
      queue = queues[(idx + ridx) % queue_count]
      POOL.with do |conn|
        conn.exec_params(
          "INSERT INTO ratomic_smoke_jobs (queue_name, payload) VALUES ($1, $2)",
          [queue, "job"]
        )
      end
    end

    [:producer_done, ridx]
  end
end

producer_results = producers.map { |worker| concurrent_value(worker) }

consumers = CONSUMERS.times.map do |consumer_index|
  concurrency_type.new(consumer_index) do |ridx|
    processed = 0

    loop do
      claimed = POOL.with do |conn|
        conn.exec_params(<<~SQL, [ridx])
          WITH claimed AS (
            SELECT id
            FROM ratomic_smoke_jobs
            WHERE processed = false
            ORDER BY id
            LIMIT 1
            FOR UPDATE SKIP LOCKED
          )
          UPDATE ratomic_smoke_jobs AS jobs
          SET processed = true,
              consumer_id = $1
          FROM claimed
          WHERE jobs.id = claimed.id
          RETURNING jobs.id
        SQL
      end

      break if claimed.ntuples.zero?

      processed += 1
    end

    [:consumer_done, ridx, processed]
  end
end

consumer_results = consumers.map { |worker| concurrent_value(worker) }

p producer_results
p consumer_results
p unprocessed_counts
p [:end, Time.now]
