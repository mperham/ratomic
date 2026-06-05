# frozen_string_literal: true

require "test_helper"

class TestRatomic < Minitest::Test
  MAX_RACTORS = 8

  def test_that_it_has_a_version_number
    refute_nil ::Ratomic::VERSION
  end

  def test_counter_counts
    c = Ratomic::Counter.new
    c.increment(1)
    c.increment(1)
    c.increment(3)
    val = c.read
    assert_equal 5, val
  end

  def test_ractor_counting
    cpus = [Etc.nprocessors, MAX_RACTORS].min
    iter = 100000
    counter = Ratomic::Counter.new
    ractors = 1.upto(cpus).map do |i|
      Ractor.new(iter, counter) do |iter, counter|
        iter.times { counter.increment(1) }
        :done
      end
    end
    assert_equal ractors.map { |ractor| ractor_value(ractor) }, [:done] * cpus, "not all workers have finished successfully"
    assert_equal counter.read, cpus * iter, "race condition"
  end
end
