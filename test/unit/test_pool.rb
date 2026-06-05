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

  def test_default_size_seeds_five_objects
    pool = Ratomic::Pool.new { [] }

    objects = 5.times.map { pool.checkout }

    assert_equal 5, objects.length
    assert objects.all? { |object| object == [] }
  ensure
    objects&.each { |object| pool.checkin(object) if object }
    pool&.close
  end

  def test_checkout_returns_pooled_object
    pool = Ratomic::Pool.new(1, 0.1) { [] }

    object = pool.checkout

    assert_equal [], object
  ensure
    pool&.checkin(object) if object
    pool&.close
  end

  def test_checkin_returns_nil
    pool = Ratomic::Pool.new(1, 0.1) { [] }
    object = pool.checkout

    assert_nil pool.checkin(object)
  ensure
    pool&.close
  end

  def test_checkout_returns_nil_after_timeout
    pool = Ratomic::Pool.new(1, 0.001) { [] }
    object = pool.checkout

    assert_nil pool.checkout
  ensure
    pool&.checkin(object) if object
    pool&.close
  end

  def test_with_raises_after_checkout_timeout
    pool = Ratomic::Pool.new(1, 0.001) { [] }
    object = pool.checkout

    assert_raises(Ratomic::Error) do
      pool.with { flunk "should not yield without an available object" }
    end
  ensure
    pool&.checkin(object) if object
    pool&.close
  end

  def test_with_returns_block_value_and_checks_object_back_in
    pool = Ratomic::Pool.new(1, 0.1) { [] }
    outside = nil

    result = pool.with do |object|
      outside = object
      object << :used
      :result
    end

    assert_equal :result, result
    assert_raises(Ractor::MovedError) { outside << :stale }

    object = pool.checkout
    assert_equal [:used], object
  ensure
    pool&.checkin(object) if object
    pool&.close
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
    pool&.close
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
    pool&.close
  end

  def test_close_stops_the_control_ractor
    pool = Ratomic::Pool.new(1, 0.1) { [] }

    assert_nil pool.close
  end

  def test_close_is_idempotent
    pool = Ratomic::Pool.new(1, 0.1) { [] }

    pool.close

    assert_nil pool.close
  end

  def test_with_checks_object_back_in_when_no_block_is_given
    pool = Ratomic::Pool.new(1, 0.1) { [] }

    assert_raises(LocalJumpError) { pool.with }

    object = pool.checkout
    assert_equal [], object
  ensure
    pool&.checkin(object) if object
    pool&.close
  end

  def test_control_checkout_sends_available_object_to_reply_port
    object = :pooled_object
    reply = Ractor::Port.new
    available = [object]
    waiting = {}

    Ratomic::Pool.send(:handle_checkout, [:request_id, reply], available, waiting)

    assert_equal object, reply.receive
    assert_empty available
    assert_empty waiting
  ensure
    reply&.close unless reply&.closed?
  end

  def test_control_checkout_records_waiter_when_pool_is_empty
    reply = Ractor::Port.new
    available = []
    waiting = {}

    Ratomic::Pool.send(:handle_checkout, [:request_id, reply], available, waiting)

    assert_empty available
    assert_same reply, waiting[:request_id]
  ensure
    reply&.close unless reply&.closed?
  end

  def test_control_checkin_stores_object_when_no_waiters_exist
    object = :pooled_object
    available = []
    waiting = {}

    Ratomic::Pool.send(:handle_checkin, object, available, waiting)

    assert_equal [object], available
    assert_empty waiting
  end

  def test_control_checkin_sends_object_to_waiting_reply_port
    object = :pooled_object
    reply = Ractor::Port.new
    available = []
    waiting = {request_id: reply}

    Ratomic::Pool.send(:handle_checkin, object, available, waiting)

    assert_equal object, reply.receive
    assert_empty available
    assert_empty waiting
  ensure
    reply&.close unless reply&.closed?
  end

  def test_control_checkin_skips_closed_reply_ports
    object = :pooled_object
    closed_reply = Ractor::Port.new
    open_reply = Ractor::Port.new
    available = []
    waiting = {closed: closed_reply, open: open_reply}
    closed_reply.close

    Ratomic::Pool.send(:handle_checkin, object, available, waiting)

    assert_equal object, open_reply.receive
    assert_empty available
    assert_empty waiting
  ensure
    open_reply&.close unless open_reply&.closed?
  end

  def test_control_command_dispatches_checkout
    object = :pooled_object
    reply = Ractor::Port.new
    available = [object]
    waiting = {}

    result = Ratomic::Pool.send(:handle_command, :checkout, [:request_id, reply], available, waiting)

    assert_same reply, result
    assert_equal object, reply.receive
    assert_empty available
    assert_empty waiting
  ensure
    reply&.close unless reply&.closed?
  end

  def test_control_command_dispatches_checkin
    object = :pooled_object
    available = []
    waiting = {}

    result = Ratomic::Pool.send(:handle_command, :checkin, [object], available, waiting)

    assert_equal [object], result
    assert_equal [object], available
    assert_empty waiting
  end

  def test_control_cancel_removes_waiter
    reply = Ractor::Port.new
    available = []
    waiting = {request_id: reply}

    Ratomic::Pool.send(:handle_command, :cancel, [:request_id], available, waiting)

    assert_empty available
    assert_empty waiting
  ensure
    reply&.close unless reply&.closed?
  end

  def test_control_shutdown_command_returns_shutdown
    available = []
    waiting = {}

    assert_equal :shutdown, Ratomic::Pool.send(:handle_command, :shutdown, [], available, waiting)
  end

  def test_control_ignores_unknown_commands
    available = []
    waiting = {}

    assert_nil Ratomic::Pool.send(:handle_command, :unknown, [], available, waiting)
    assert_empty available
    assert_empty waiting
  end
end
