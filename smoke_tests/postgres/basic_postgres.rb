# Run with `bundle exec ruby postgres/basic_postgres.rb`
require "ratomic"
require "pg"

PostgresFactory = Data.define(:database_url) do
  def call
    PG.connect(database_url)
  end
end

DATABASE_URL = Ractor.make_shareable(ENV.fetch("DATABASE_URL", "postgresql://ratomic:ratomic@localhost:5432/ratomic_smoke").dup.freeze)
KEYS = Ractor.make_shareable(%w[one two three four five].map(&:freeze).freeze)
POOL = Ratomic::LocalPool.new(
  size: Integer(ENV.fetch("POOL_SIZE", "10")),
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
      CREATE TABLE IF NOT EXISTS ratomic_smoke_counts (
        name text PRIMARY KEY,
        count integer NOT NULL DEFAULT 0
      )
    SQL
    conn.exec("TRUNCATE ratomic_smoke_counts")
  end
end

def snapshot_counts
  POOL.with do |conn|
    result = conn.exec("SELECT name, count FROM ratomic_smoke_counts ORDER BY name")
    result.map { |row| { row.fetch("name") => Integer(row.fetch("count")) } }
  end
end

[Thread, Ractor].each do |klass|
  setup_database

  ending = Time.now + Integer(ENV.fetch("SECONDS", "10"))
  workers = 5.times.map do |worker_index|
    klass.new(KEYS, ending, worker_index) do |keys, stop, idx|
      processed = 0

      loop do
        key = keys[(processed + idx) % keys.size]
        POOL.with do |conn|
          conn.exec_params(<<~SQL, [key])
            INSERT INTO ratomic_smoke_counts (name, count)
            VALUES ($1, 1)
            ON CONFLICT (name)
            DO UPDATE SET count = ratomic_smoke_counts.count + 1
          SQL
        end
        processed += 1
        break if Time.now > stop
      end

      processed
    end
  end

  worker_counts = workers.map { |worker| concurrent_value(worker) }
  p(klass, worker_counts, snapshot_counts)
end
