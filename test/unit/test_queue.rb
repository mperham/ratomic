# frozen_string_literal: true

require "test_helper"

class QueueUnitTest < Minitest::Test
  def test_new_queue_is_empty
    queue = Ratomic::Queue.new(4)

    assert_predicate queue, :empty?
    assert_equal 0, queue.size
    assert_equal 0, queue.length
    assert_nil queue.peek
  end

  def test_push_pop_fifo_and_append_alias
    queue = Ratomic::Queue.new(4)

    assert_same queue, queue << :first
    queue.push(:second)

    assert_equal 2, queue.size
    assert_equal :first, queue.peek
    assert_equal 2, queue.size
    assert_equal :first, queue.pop
    assert_equal :second, queue.pop
    assert_predicate queue, :empty?
  end

  def test_rejects_invalid_capacity
    assert_raises(TypeError) { Ratomic::Queue.new("4") }
    assert_raises(TypeError) { Ratomic::Queue.new(4.0) }
    assert_raises(ArgumentError) { Ratomic::Queue.new(0) }
    assert_raises(ArgumentError) { Ratomic::Queue.new(2**20 + 1) }
  end

  def test_queue_transfers_items_between_ractors
    queue = Ratomic::Queue.new(4)

    producer = Ractor.new(queue) do |ractor_queue|
      ractor_queue << [:change, 1]
      :done
    end

    assert_equal :done, ractor_value(producer)
    assert_equal [:change, 1], queue.pop
  end
end
