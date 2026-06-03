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
end
