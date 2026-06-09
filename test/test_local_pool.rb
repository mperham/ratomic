# frozen_string_literal: true

require "test_helper"

class TestLocalPool < Minitest::Test
  class ArrayFactory
    def call
      []
    end
  end

  class Closable
    attr_reader :closed

    def initialize
      @closed = false
    end

    def close
      @closed = true
    end
  end

  FACTORY = Ractor.make_shareable(ArrayFactory.new.freeze)

  def test_pool_is_shareable
    pool = Ratomic::LocalPool.new(factory: FACTORY)
    assert Ractor.shareable?(pool)
  end

  def test_requires_positive_integer_size
    assert_raises(ArgumentError) { Ratomic::LocalPool.new(size: 0, factory: FACTORY) }
    assert_raises(ArgumentError) { Ratomic::LocalPool.new(size: 1.5, factory: FACTORY) }
  end

  def test_requires_numeric_timeout
    assert_raises(ArgumentError) do
      Ratomic::LocalPool.new(timeout: "foo", factory: FACTORY)
    end
  end

  def test_requires_non_negative_timeout
    assert_raises(ArgumentError) do
      Ratomic::LocalPool.new(size: 1, timeout: -1, factory: FACTORY)
    end
  end

  def test_requires_factory
    assert_raises(LocalJumpError) do
      Ratomic::LocalPool.new
    end
  end

  def test_rejects_factory_and_block
    assert_raises(ArgumentError) do
      Ratomic::LocalPool.new(factory: FACTORY) { [] }
    end
  end

  def test_rejects_non_callable_factory
    factory = Ractor.make_shareable(Object.new.freeze)

    assert_raises(ArgumentError) do
      Ratomic::LocalPool.new(factory: factory)
    end
  end

  def test_requires_shareable_factory
    error = assert_raises(ArgumentError) do
      Ratomic::LocalPool.new { [] }
    end

    assert_match(/factory must be Ractor-shareable/, error.message)
  end

  def test_close_before_initialization_is_noop
    pool = Ratomic::LocalPool.new(factory: FACTORY)
    assert_nil pool.close
  end

  def test_threads_share_current_local_pool
    pool = Ratomic::LocalPool.new(size: 1, timeout: 0.1, factory: FACTORY)
    object_ids = Queue.new

    3.times.map do
      Thread.new do
        pool.with do |object|
          object_ids << object.object_id
        end
      end
    end.each(&:join)

    assert_equal 1, 3.times.map { object_ids.pop }.uniq.size
  ensure
    pool&.close
  end

  def test_each_ractor_gets_its_own_local_pool
    pool = Ratomic::LocalPool.new(size: 1, timeout: 0.1, factory: FACTORY)

    results = 2.times.map do
      Ractor.new(pool) do |local_pool|
        first = nil
        second = nil

        local_pool.with { |object| first = object.object_id }
        local_pool.with { |object| second = object.object_id }

        local_pool.close
        [first == second, first]
      end
    end.map { |ractor| ractor_value(ractor) }

    assert results.all?(&:first)
    refute_equal results[0][1], results[1][1]
  end

  def test_timeout_raises_ratomic_error
    pool = Ratomic::LocalPool.new(size: 1, timeout: 0.01, factory: FACTORY)
    error = nil

    pool.with do
      thread = Thread.new do
        begin
          pool.with { |_object| :unreachable }
        rescue Ratomic::Error => e
          error = e
        end
      end
      thread.join
    end

    assert_instance_of Ratomic::Error, error
    assert_match(/pool checkout timeout/, error.message)
  ensure
    pool&.close
  end

  def test_close_closes_available_resources
    resource = Closable.new

    factory = Class.new do
      define_method(:call) { resource }
    end.new

    Ractor.make_shareable(factory)

    pool = Ratomic::LocalPool.new(factory: factory)

    pool.with { |_obj| nil }
    pool.close

    assert resource.closed
  end

  def test_factory_failure_propagates
    factory = Class.new do
      def call
        raise "boom"
      end
    end.new

    Ractor.make_shareable(factory)

    pool = Ratomic::LocalPool.new(factory: factory)

    error = assert_raises(RuntimeError) do
      pool.with { }
    end

    assert_equal "boom", error.message
  end
end
