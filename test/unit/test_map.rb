# frozen_string_literal: true

require "test_helper"

class MapUnitTest < Minitest::Test
  def test_new_map_is_empty
    map = Ratomic::Map.new

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
