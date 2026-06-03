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

    counter.inc(5)
    counter.dec(2)
    counter.decrement(3)

    assert_equal 0, counter.read
    assert_predicate counter, :zero?
  end

  def test_rejects_negative_wrapper_amounts
    counter = Ratomic::Counter.new

    assert_raises(ArgumentError) { counter.inc(-1) }
    assert_raises(ArgumentError) { counter.dec(-1) }
  end

  def test_counter_is_shareable
    counter = Ratomic::Counter.new

    worker = Ractor.new(counter) do |ractor_counter|
      ractor_counter.inc(2)
      ractor_counter.to_i
    end

    assert_equal 2, ractor_value(worker)
    assert_equal 2, counter.to_i
  end
end
