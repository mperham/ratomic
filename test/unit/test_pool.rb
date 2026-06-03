# frozen_string_literal: true

require "test_helper"

class PoolUnitTest < Minitest::Test
  def test_requires_positive_size
    assert_raises(ArgumentError) do
      Ratomic::Pool.new(0) { [] }
    end
  end

  def test_requires_factory_block
    assert_raises(LocalJumpError) do
      Ratomic::Pool.new(1)
    end
  end

  def test_checkout_returns_pooled_object
    pool = Ratomic::Pool.new(1, 0.1) { [] }

    object = pool.checkout

    assert_equal [], object
  ensure
    pool&.checkin(object) if object
  end

  def test_checkin_returns_nil
    pool = Ratomic::Pool.new(1, 0.1) { [] }
    object = pool.checkout

    assert_nil pool.checkin(object)
  end

  def test_checkout_returns_nil_after_timeout
    pool = Ratomic::Pool.new(1, 0.001) { [] }
    object = pool.checkout

    assert_nil pool.checkout
  ensure
    pool&.checkin(object) if object
  end

  def test_with_raises_after_checkout_timeout
    pool = Ratomic::Pool.new(1, 0.001) { [] }
    object = pool.checkout

    assert_raises(Ratomic::Error) do
      pool.with { flunk "should not yield without an available object" }
    end
  ensure
    pool&.checkin(object) if object
  end

  def test_with_checks_object_back_in_when_block_raises
    pool = Ratomic::Pool.new(1, 0.1) { [] }
    outside = nil

    assert_raises(RuntimeError) do
      pool.with do |object|
        outside = object
        object << :before_error
        raise "boom"
      end
    end

    assert_raises(Ractor::MovedError) do
      outside << :after_error
    end

    object = pool.checkout
    assert_equal [:before_error], object
  ensure
    pool&.checkin(object) if object
  end

  def test_nil_timeout_waits_until_object_is_available
    pool = Ratomic::Pool.new(1, nil) { [] }
    object = pool.checkout

    worker = Ractor.new(pool) do |ractor_pool|
      ractor_pool.checkout
    end

    sleep 0.05
    pool.checkin(object)

    checked_out = ractor_value(worker)
    assert_equal [], checked_out
  ensure
    pool&.checkin(checked_out) if checked_out
  end
end
