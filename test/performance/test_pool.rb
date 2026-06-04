# frozen_string_literal: true

require "test_helper"

class PoolPerformanceTest < Minitest::Test
  ITERATIONS = 1_000

  def test_repeated_with_completes_within_smoke_threshold
    skip "set RATOMIC_PERFORMANCE_TESTS=1" unless ENV["RATOMIC_PERFORMANCE_TESTS"] == "1"

    pool = Ratomic::Pool.new(4, 1.0) { [] }

    elapsed = measure do
      ITERATIONS.times do |index|
        pool.with { |object| object << index }
      end
    end

    assert_operator elapsed, :<, 10.0
  end

  def test_concurrent_with_completes_within_smoke_threshold
    skip "set RATOMIC_PERFORMANCE_TESTS=1" unless ENV["RATOMIC_PERFORMANCE_TESTS"] == "1"

    pool = Ratomic::Pool.new(Etc.nprocessors, 1.0) { [] }

    elapsed = measure do
      workers = Etc.nprocessors.times.map do
        Ractor.new(pool) do |ractor_pool|
          ITERATIONS.times { |index| ractor_pool.with { |object| object << index } }
          :done
        end
      end

      assert_equal [:done] * workers.length, workers.map { |worker| ractor_value(worker) }
    end

    assert_operator elapsed, :<, 10.0
  end

  private

  def measure
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end
end
