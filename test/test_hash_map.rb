require "test_helper"

class TestHashMap < Minitest::Test
  MAX_RACTORS = 8
  MAP = Ratomic::Map.new

  def test_ractor_hashing
    MAP.clear
    cpus = [Etc.nprocessors, MAX_RACTORS].min
    iter = 100000
    ractors = 1.upto(cpus).map do |i|
      Ractor.new(iter) do |iter|
        iter.times { |idx| MAP.set(idx, (iter + idx)) }
        iter.times { |idx| MAP[idx] = (iter + idx) }
        :done
      end
    end
    assert_equal ractors.map { |ractor| ractor_value(ractor) }, [:done] * cpus, "not all workers have finished successfully"
    1000.times do |idx|
      assert_equal iter+idx, MAP.get(idx)
      assert_equal iter+idx, MAP[idx]
    end
  end

  def test_size_no_ractors
    MAP.clear
    assert_equal 0, MAP.size
    MAP.set(1, 2)
    assert_equal 1, MAP.size
    MAP.set(2, 3)
    assert_equal 2, MAP.size
    MAP.clear
    assert_equal 0, MAP.size
  end

  def test_size_with_ractors
    MAP.clear
    cpus = [Etc.nprocessors, MAX_RACTORS].min
    iter = 100_000
    ractors = 1.upto(cpus).map do |i|
      Ractor.new(iter) do |iter|
        iter.times { |idx| MAP[idx] = (iter + idx) }
        :done
      end
    end
    ractors.map { |ractor| ractor_value(ractor) }

    assert_equal 100_000, MAP.size
  end
end
