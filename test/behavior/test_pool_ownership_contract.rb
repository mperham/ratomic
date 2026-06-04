# frozen_string_literal: true

require "test_helper"

class PoolOwnershipContractTest < Minitest::Test
  def test_checked_in_object_is_moved_from_caller_after_with
    pool = Ratomic::Pool.new(1, 0.1) { [] }
    outside = nil

    pool.with do |object|
      outside = object
      object << :inside
    end

    assert_raises(Ractor::MovedError) do
      outside << :outside
    end
  end

  def test_checked_in_object_is_moved_from_caller_after_manual_checkin
    pool = Ratomic::Pool.new(1, 0.1) { [] }
    object = pool.checkout

    pool.checkin(object)

    assert_raises(Ractor::MovedError) do
      object << :outside
    end
  end

  def test_pool_can_transfer_mutable_objects_between_ractors
    pool = Ratomic::Pool.new(2, 0.1) { [] }

    workers = 4.times.map do |worker_id|
      Ractor.new(pool, worker_id) do |ractor_pool, id|
        25.times do |index|
          ractor_pool.with { |object| object << [id, index] }
        end
        :done
      end
    end

    assert_equal [:done] * workers.length, workers.map { |worker| ractor_value(worker) }

    pooled_objects = 2.times.map { pool.checkout }
    flattened_entries = pooled_objects.flatten(1)

    assert_equal 100, flattened_entries.length
    assert_equal (0...4).to_a, flattened_entries.map(&:first).uniq.sort
  ensure
    pooled_objects&.each { |object| pool.checkin(object) }
  end
end
