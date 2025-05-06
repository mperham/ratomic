require "test_helper"

class TestMpmcQueue < Minitest::Test
  QUEUE_CAPACITY = 128  
  TOTAL_ITEMS = 50

  def setup
    @queue = Ratomic::Queue.new(QUEUE_CAPACITY)
  end

  def test_basic_operations
    assert @queue.empty?, "initial queue should be empty"
    assert_equal 0, @queue.size, "initial size should be 0"
    assert_nil @queue.peek, "peek on empty queue should be nil"

    @queue.push(:a)
    refute @queue.empty?, "queue should not be empty after push"
    assert_equal 1, @queue.size, "size should be 1 after push"
    assert_equal :a, @queue.peek, "peek should return the pushed item"
    assert_equal 1, @queue.size, "size should be unchanged after peek" 

    item = @queue.pop
    assert_equal :a, item, "pop should return the pushed item"
    assert @queue.empty?, "queue should be empty after pop"
    assert_equal 0, @queue.size, "size should be 0 after pop"
  end

  def test_pop_waits_for_item
    blocker = Ractor.new(@queue) { |q| q.pop }

    sleep 0.05

    # There is currently no public API to check the status of a Ractor
    assert blocker.inspect.include?("blocking"), "should be blocked waiting for pop"

    @queue.push(123)
    result = nil
    50.times { result = blocker.take rescue nil; break if result; sleep 0.01 }

    assert_equal 123, result, "did not receive the pushed item"
  end

  def test_push_waits_for_free_space
    QUEUE_CAPACITY.times { |i| @queue.push("fill_#{i}") }
    assert_equal QUEUE_CAPACITY, @queue.size

    blocker = Ractor.new(@queue) do |q|
      q.push("extra")
      :pushed 
    end

    assert blocker.inspect.include?("blocking"), "should be blocked waiting for free space"

    @queue.pop

    result = nil
    50.times { result = blocker.take rescue nil; break if result; sleep 0.01 } 
    assert_equal :pushed, result, "did not signal successful push"

    remaining_items = []
    QUEUE_CAPACITY.times { remaining_items << @queue.pop } 
    assert_includes remaining_items, "extra", "'extra' item pushed by the Ractor was not found"
  end

  def test_mpmc_concurrent_transfer
    num_producers = Etc.nprocessors / 2
    num_consumers = Etc.nprocessors / 2
    items_per_producer = (TOTAL_ITEMS.to_f / num_producers).ceil 
    actual_total_items = items_per_producer * num_producers 

    producers = num_producers.times.map do |p_idx|
      Ractor.new(@queue, items_per_producer, p_idx) do |q, count, id|
        start_num = id * count
        count.times do |i|
          q.push(start_num + i)
        end
        :done_producing
      end
    end

    consumers = num_consumers.times.map do
      Ractor.new(@queue) do |q|
        loop do
          item = q.pop
          break if item == :__TERMINATE__ 
          Ractor.yield item
        end
      end
    end

    sleep 0.1

    producers.each { |p| assert_equal :done_producing, p.take }

    results = []
    actual_total_items.times do |i|
      _, value = Ractor.select(*consumers)
      results << value
    rescue Ractor::ClosedError, Ractor::RemoteError, Ractor::Error => e
      flunk "consumer Ractor closed unexpectedly: #{e.message}"
      break
    end

    num_consumers.times do
      @queue.push(:__TERMINATE__)
    end

    assert_equal actual_total_items, results.size, "did not receive the expected number of items"
    assert_equal (0...actual_total_items).to_a, results.sort, "set of popped items does not match the set of pushed items"

    assert @queue.empty?, "queue should be empty after items are popped. Size: #{@queue.size}"
    assert_equal 0, @queue.size
  end
end