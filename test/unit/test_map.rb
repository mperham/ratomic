# frozen_string_literal: true

require "test_helper"

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

  def test_fetch_returns_stored_nil_value
    map = Ratomic::Map.new
    map[:source] = nil

    assert_nil map.fetch(:source)
  end

  def test_fetch_returns_default_for_missing_key
    map = Ratomic::Map.new

    assert_equal "fallback", map.fetch(:missing, "fallback")
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
end
