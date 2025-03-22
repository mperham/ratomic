require "test_helper"

class TestPool < Minitest::Test
  POOL_SIZE = 5
  objects = 1.upto(POOL_SIZE).map { |i| ["pool-object-#{i}"] }
  POOL = Ratomic::Pool.new(POOL_SIZE, 0.1) { objects.shift }

  def test_pooling
    ractors = 1.upto(POOL_SIZE).map do |i|
      Ractor.new(i) do |i|
        10.times do |j|
          POOL.with do |v|
            v.push([i, j])
          end
        end

        Ractor.yield :done
      end
    end

    ractors.map(&:take)
    POOL_SIZE.times do
      #p POOL.checkout
      POOL.checkout
    end
    # 100ms timeout
    refute POOL.checkout
  end
end