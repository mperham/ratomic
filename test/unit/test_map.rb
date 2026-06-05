# frozen_string_literal: true

require "test_helper"
require "set"

class MapUnitTest < Minitest::Test
  def test_new_map_is_empty
    map = Ratomic::Map.new

    assert_equal Ratomic::Map, map.class
    assert_match "#<Ratomic::Map:", map.inspect
    assert_equal 0, map.size
    assert_equal 0, map.length
    assert_predicate map, :empty?
  end

  def test_set_get_and_clear
    map = Ratomic::Map.new

    map[:source] = "postgres"
    map.set(:offset, 42)

    assert_equal "postgres", map[:source]
    assert_equal 42, map.get(:offset)
    assert_equal 2, map.length
    refute_predicate map, :empty?

    map.clear

    assert_nil map[:source]
    assert_predicate map, :empty?
  end

  def test_key_predicates_distinguish_missing_keys_from_nil_values
    map = Ratomic::Map.new

    refute map.key?(:source)
    refute map.include?(:source)
    refute map.member?(:source)

    map[:source] = nil

    assert map.key?(:source)
    assert map.include?(:source)
    assert map.member?(:source)
    assert_nil map[:source]
  end

  def test_delete_removes_entry_and_returns_previous_value
    map = Ratomic::Map.new
    map[:source] = "postgres"

    assert_equal "postgres", map.delete(:source)
    refute map.key?(:source)
    assert_nil map[:source]
  end

  def test_delete_returns_nil_for_missing_key
    map = Ratomic::Map.new

    assert_nil map.delete(:missing)
  end

  def test_delete_returns_nil_for_stored_nil_value
    map = Ratomic::Map.new
    map[:source] = nil

    assert_nil map.delete(:source)
    refute map.key?(:source)
  end

  def test_fetch_returns_existing_value
    map = Ratomic::Map.new
    map[:source] = "postgres"

    assert_equal "postgres", map.fetch(:source)
  end

  def test_fetch_does_not_yield_for_existing_key
    map = Ratomic::Map.new
    map[:source] = "postgres"

    result = map.fetch(:source) { flunk "should not yield for existing key" }

    assert_equal "postgres", result
  end

  def test_fetch_returns_stored_nil_value
    map = Ratomic::Map.new
    map[:source] = nil

    assert_nil map.fetch(:source)
  end

  def test_fetch_returns_default_for_missing_key
    map = Ratomic::Map.new

    assert_equal "fallback", map.fetch(:missing, "fallback")
    refute map.key?(:missing)
  end

  def test_fetch_yields_missing_key
    map = Ratomic::Map.new

    assert_equal "fallback for missing", map.fetch(:missing) { |key| "fallback for #{key}" }
  end

  def test_fetch_block_takes_precedence_over_default
    map = Ratomic::Map.new

    assert_equal "block fallback", map.fetch(:missing, "default fallback") { "block fallback" }
  end

  def test_fetch_raises_key_error_for_missing_key_without_default
    map = Ratomic::Map.new

    error = assert_raises(KeyError) { map.fetch(:missing) }

    assert_equal "key not found: :missing", error.message
  end

  def test_fetch_and_modify_updates_existing_value
    map = Ratomic::Map.new
    map[:processed] = 1

    map.fetch_and_modify(:processed) { |value| value + 41 }

    assert_equal 42, map[:processed]
  end

  def test_fetch_and_modify_does_not_yield_for_missing_key
    map = Ratomic::Map.new

    map.fetch_and_modify(:processed) { flunk "should not yield for missing key" }

    refute map.key?(:processed)
  end

  def test_fetch_and_modify_requires_a_block
    map = Ratomic::Map.new
    map[:processed] = 1

    assert_raises(LocalJumpError) { map.fetch_and_modify(:processed) }
  end

  def test_fetch_and_modify_propagates_block_exception
    map = Ratomic::Map.new
    map[:processed] = 1

    error = assert_raises(RuntimeError) do
      map.fetch_and_modify(:processed) { raise "boom" }
    end

    assert_equal "boom", error.message
    assert_equal 1, map[:processed]
  end

  def test_compute_updates_existing_value_and_returns_new_value
    map = Ratomic::Map.new
    map[:processed] = 1

    result = map.compute(:processed) { |value| value + 41 }

    assert_equal 42, result
    assert_equal 42, map[:processed]
  end

  def test_compute_inserts_missing_key
    map = Ratomic::Map.new

    result = map.compute(:processed) { |value| value.to_i + 1 }

    assert_equal 1, result
    assert_equal 1, map[:processed]
  end

  def test_compute_yields_stored_nil_value
    map = Ratomic::Map.new
    map[:processed] = nil

    result = map.compute(:processed) { |value| value.nil? ? 1 : 0 }

    assert_equal 1, result
    assert_equal 1, map[:processed]
  end

  def test_compute_requires_a_block
    map = Ratomic::Map.new

    assert_raises(LocalJumpError) { map.compute(:processed) }
  end

  def test_compute_preserves_existing_value_when_block_raises
    map = Ratomic::Map.new
    map[:processed] = 1

    error = assert_raises(RuntimeError) do
      map.compute(:processed) { raise "boom" }
    end

    assert_equal "boom", error.message
    assert_equal 1, map[:processed]
  end

  def test_compute_does_not_insert_missing_key_when_block_raises
    map = Ratomic::Map.new

    error = assert_raises(RuntimeError) do
      map.compute(:processed) { raise "boom" }
    end

    assert_equal "boom", error.message
    refute map.key?(:processed)
  end

  def test_fetch_or_store_returns_existing_value_without_yielding
    map = Ratomic::Map.new
    map[:source] = "postgres"

    result = map.fetch_or_store(:source) { flunk "should not yield for existing key" }

    assert_equal "postgres", result
    assert_equal "postgres", map[:source]
  end

  def test_fetch_or_store_stores_and_returns_block_value_for_missing_key
    map = Ratomic::Map.new

    result = map.fetch_or_store(:source) { "postgres" }

    assert_equal "postgres", result
    assert_equal "postgres", map[:source]
  end

  def test_fetch_or_store_treats_stored_nil_as_existing_value
    map = Ratomic::Map.new
    map[:source] = nil

    result = map.fetch_or_store(:source) { flunk "should not yield for stored nil" }

    assert_nil result
    assert map.key?(:source)
  end

  def test_fetch_or_store_requires_a_block
    map = Ratomic::Map.new

    assert_raises(LocalJumpError) { map.fetch_or_store(:source) }
  end

  def test_fetch_or_store_does_not_insert_missing_key_when_block_raises
    map = Ratomic::Map.new

    error = assert_raises(RuntimeError) do
      map.fetch_or_store(:source) { raise "boom" }
    end

    assert_equal "boom", error.message
    refute map.key?(:source)
  end

  def test_upsert_inserts_initial_value_for_missing_key_without_yielding
    map = Ratomic::Map.new

    result = map.upsert(:processed, 1) { flunk "should not yield for missing key" }

    assert_equal 1, result
    assert_equal 1, map[:processed]
  end

  def test_upsert_updates_existing_value_and_returns_new_value
    map = Ratomic::Map.new
    map[:processed] = 1

    result = map.upsert(:processed, 1) { |value| value + 41 }

    assert_equal 42, result
    assert_equal 42, map[:processed]
  end

  def test_upsert_yields_stored_nil_value
    map = Ratomic::Map.new
    map[:processed] = nil

    result = map.upsert(:processed, 1) { |value| value.nil? ? 2 : 0 }

    assert_equal 2, result
    assert_equal 2, map[:processed]
  end

  def test_upsert_requires_a_block
    map = Ratomic::Map.new

    assert_raises(LocalJumpError) { map.upsert(:processed, 1) }
  end

  def test_upsert_preserves_existing_value_when_block_raises
    map = Ratomic::Map.new
    map[:processed] = 1

    error = assert_raises(RuntimeError) do
      map.upsert(:processed, 1) { raise "boom" }
    end

    assert_equal "boom", error.message
    assert_equal 1, map[:processed]
  end

  def test_increment_initializes_missing_key
    map = Ratomic::Map.new

    result = map.increment(:processed)

    assert_equal 1, result
    assert_equal 1, map[:processed]
  end

  def test_increment_adds_amount_to_existing_numeric_value
    map = Ratomic::Map.new
    map[:processed] = 10

    result = map.increment(:processed, 5)

    assert_equal 15, result
    assert_equal 15, map[:processed]
  end

  def test_decrement_subtracts_amount
    map = Ratomic::Map.new
    map[:processed] = 10

    result = map.decrement(:processed, 4)

    assert_equal 6, result
    assert_equal 6, map[:processed]
  end

  def test_decrement_initializes_missing_key
    map = Ratomic::Map.new

    result = map.decrement(:processed, 4)

    assert_equal(-4, result)
    assert_equal(-4, map[:processed])
  end

  def test_increment_requires_numeric_amount
    map = Ratomic::Map.new

    assert_raises(TypeError) { map.increment(:processed, "1") }
    refute map.key?(:processed)
  end

  def test_decrement_requires_numeric_amount
    map = Ratomic::Map.new

    assert_raises(TypeError) { map.decrement(:processed, "1") }
    refute map.key?(:processed)
  end

  def test_decrement_rejects_existing_non_numeric_value
    map = Ratomic::Map.new
    map[:processed] = "ten"

    error = assert_raises(TypeError) { map.decrement(:processed) }

    assert_match "existing value for :processed must be numeric", error.message
    assert_equal "ten", map[:processed]
  end

  def test_increment_rejects_existing_non_numeric_value
    map = Ratomic::Map.new
    map[:processed] = "ten"

    error = assert_raises(TypeError) { map.increment(:processed) }

    assert_match "existing value for :processed must be numeric", error.message
    assert_equal "ten", map[:processed]
  end

  def test_increment_rejects_existing_nil_value
    map = Ratomic::Map.new
    map[:processed] = nil

    error = assert_raises(TypeError) { map.increment(:processed) }

    assert_match "existing value for :processed must be numeric", error.message
    assert_nil map[:processed]
    assert map.key?(:processed)
  end

  def test_append_initializes_array_bucket
    map = Ratomic::Map.new

    result = map.append(:events, "created")

    assert_equal ["created"], result
    assert_predicate result, :frozen?
    assert_equal ["created"], map[:events]
  end

  def test_append_replaces_existing_array_bucket
    map = Ratomic::Map.new
    original = ["created"]
    map[:events] = original

    result = map.append(:events, "updated")

    assert_equal ["created"], original
    assert_equal ["created", "updated"], result
    assert_predicate result, :frozen?
    assert_equal ["created", "updated"], map[:events]
  end

  def test_append_rejects_existing_non_array_value
    map = Ratomic::Map.new
    map[:events] = "created"

    error = assert_raises(TypeError) { map.append(:events, "updated") }

    assert_match "existing value for :events must be an Array", error.message
    assert_equal "created", map[:events]
  end

  def test_append_rejects_existing_nil_value
    map = Ratomic::Map.new
    map[:events] = nil

    error = assert_raises(TypeError) { map.append(:events, "updated") }

    assert_match "existing value for :events must be an Array", error.message
    assert_nil map[:events]
    assert map.key?(:events)
  end

  def test_add_to_set_initializes_set_bucket
    map = Ratomic::Map.new

    result = map.add_to_set(:workers, :a)

    assert_equal Set[:a], result
    assert_predicate result, :frozen?
    assert_equal Set[:a], map[:workers]
  end

  def test_add_to_set_replaces_existing_set_bucket
    map = Ratomic::Map.new
    original = Set[:a]
    map[:workers] = original

    result = map.add_to_set(:workers, :b)

    assert_equal Set[:a], original
    assert_equal Set[:a, :b], result
    assert_predicate result, :frozen?
    assert_equal Set[:a, :b], map[:workers]
  end

  def test_add_to_set_rejects_existing_non_set_value
    map = Ratomic::Map.new
    map[:workers] = [:a]

    error = assert_raises(TypeError) { map.add_to_set(:workers, :b) }

    assert_match "existing value for :workers must be a Set", error.message
    assert_equal [:a], map[:workers]
  end

  def test_add_to_set_rejects_existing_nil_value
    map = Ratomic::Map.new
    map[:workers] = nil

    error = assert_raises(TypeError) { map.add_to_set(:workers, :b) }

    assert_match "existing value for :workers must be a Set", error.message
    assert_nil map[:workers]
    assert map.key?(:workers)
  end

  def test_map_is_shareable
    map = Ratomic::Map.new
    map[:events] = 0

    worker = Ractor.new(map) do |ractor_map|
      ractor_map.fetch_and_modify(:events) { |value| value + 5 }
      ractor_map[:events]
    end

    assert_equal 5, ractor_value(worker)
    assert_equal 5, map[:events]
  end

  def test_increment_updates_atomically_across_ractors
    map = Ratomic::Map.new

    workers = 4.times.map do
      Ractor.new(map) do |ractor_map|
        25.times do
          ractor_map.increment(:events)
        end
        :done
      end
    end

    assert_equal [:done] * workers.length, (workers.map { |worker| ractor_value(worker) })
    assert_equal 100, map[:events]
  end
end
