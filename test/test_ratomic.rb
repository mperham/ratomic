# frozen_string_literal: true

require "test_helper"

class TestRatomic < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Ratomic::VERSION
  end

  def test_counter_counts
    c = Ratomic::Counter.new
    c.inc
    c.increment(1)
    c.inc(3)
    val = c.read
    assert_equal 5, val
  end

  def test_ractor_counting
    cpus = Etc.nprocessors
    iter = 100000
    counter = Ratomic::Counter.new
    ractors = 1.upto(cpus).map do |i|
      Ractor.new(iter, counter) do |iter, counter|
        iter.times { counter.inc }
        Ractor.yield :done
      end
    end
    assert_equal ractors.map(&:take), [:done] * cpus, "not all workers have finished successfully"
    assert_equal counter.read, cpus * iter, "race condition"
  end
end
