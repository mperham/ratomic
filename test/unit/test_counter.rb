# frozen_string_literal: true

require "test_helper"

class CounterUnitTest < Minitest::Test
  def test_new_counter_starts_at_zero
    counter = Ratomic::Counter.new

    assert_equal 0, counter.read
    assert_equal 0, counter.value
    assert_equal 0, counter.to_i
    assert_predicate counter, :zero?
  end

  def test_increment_and_decrement_return_to_zero
    counter = Ratomic::Counter.new

    assert_equal 5, counter.increment(5)
    assert_equal 3, counter.decrement(2)
    assert_equal 0, counter.decrement(3)

    assert_equal 0, counter.read
    assert_predicate counter, :zero?
  end

  def test_short_increment_and_decrement_aliases_are_not_defined
    counter = Ratomic::Counter.new

    refute_respond_to counter, :inc
    refute_respond_to counter, :dec
  end

  def test_counter_is_shareable
    counter = Ratomic::Counter.new

    worker = Ractor.new(counter) do |ractor_counter|
      ractor_counter.increment(2)
      ractor_counter.to_i
    end

    assert_equal 2, ractor_value(worker)
    assert_equal 2, counter.to_i
  end
end
