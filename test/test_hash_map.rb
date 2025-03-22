require "test_helper"

class TestHashMap < Minitest::Test
  MAP = Ratomic::Map.new

  def test_ractor_hashing
    cpus = Etc.nprocessors
    iter = 100000
    ractors = 1.upto(cpus).map do |i|
      Ractor.new(iter) do |iter|
        iter.times { |idx| MAP.set(idx, (iter + idx)) }
        iter.times { |idx| MAP[idx] = (iter + idx) }
        Ractor.yield :done
      end
    end
    assert_equal ractors.map(&:take), [:done] * cpus, "not all workers have finished successfully"
    1000.times do |idx|
      assert_equal iter+idx, MAP.get(idx)
      assert_equal iter+idx, MAP[idx]
    end
  end
end