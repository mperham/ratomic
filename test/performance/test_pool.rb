# frozen_string_literal: true

require "test_helper"

class PoolPerformanceTest < Minitest::Test
  ITERATIONS = 1_000
  MAX_WORKERS = 8

  def test_repeated_with_completes_within_smoke_threshold
    skip "set RATOMIC_PERFORMANCE_TESTS=1" unless ENV["RATOMIC_PERFORMANCE_TESTS"] == "1"

    pool = Ratomic::Pool.new(4, 1.0) { [] }

    elapsed = measure do
      ITERATIONS.times do |index|
        pool.with { |object| object << index }
      end
    end

    assert_operator elapsed, :<, 10.0
  ensure
    pool&.close
  end

  def test_concurrent_with_completes_within_smoke_threshold
    skip "set RATOMIC_PERFORMANCE_TESTS=1" unless ENV["RATOMIC_PERFORMANCE_TESTS"] == "1"

    worker_count = [Etc.nprocessors, MAX_WORKERS].min
    pool = Ratomic::Pool.new(worker_count, 1.0) { [] }

    elapsed = measure do
      workers = concurrent_pool_workers(pool, worker_count)
      results = workers.map { |worker| ractor_value(worker) }

      assert_equal [:done] * workers.length, results
    end

    assert_operator elapsed, :<, 10.0
  ensure
    pool&.close
  end

  private

  def measure
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end

  def concurrent_pool_workers(pool, worker_count)
    worker_count.times.map do
      Ractor.new(pool) do |ractor_pool|
        ITERATIONS.times { |index| ractor_pool.with { |object| object << index } }
        :done
      end
    end
  end
end
