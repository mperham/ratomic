# frozen_string_literal: true

require "timeout"

module Ratomic
  # Design Note
  #
  # LocalPool originated while investigating Redis clients under Ruby
  # Ractors. The original goal was to reuse Pool, but ownership-transfer
  # semantics proved incompatible with live resources containing internal
  # state.
  #
  # The resulting architecture became known as the "Inception Pool"
  # design:
  #
  #   LocalPool facade
  #          ↓
  #   Ractor-local pool
  #          ↓
  #   Live resources
  #
  # or informally:
  #
  #   Pool
  #     ↓
  #   Pool
  #     ↓
  #   Resource
  #
  # The public API intentionally uses the more descriptive name `LocalPool`.
  #
  # A shareable facade over resources that stay local to each Ractor.
  #
  # LocalPool is intended for live resources such as Redis clients,
  # database connections, sockets, and other objects which must not be moved
  # between Ractors. The facade itself is shareable, but each Ractor lazily
  # creates and owns an independent thread-safe local pool. Threads inside the
  # same Ractor share that local pool; different Ractors never share the live
  # resources.
  #
  # This is the correct shape for resources with process, socket, connection,
  # or native state. Move work across Ractor boundaries, not live clients.
  #
  # The factory must be Ractor-shareable because the facade stores it and each
  # Ractor calls it when its local resource pool needs to create a resource. Prefer a
  # small immutable callable object instead of a block when the pool will be
  # used from multiple Ractors.
  #
  # @example Redis clients owned by each Ractor
  #   RedisFactory = Data.define(:host) do
  #     def call
  #       RedisClient.new(host: host)
  #     end
  #   end
  #
  #   REDIS = Ratomic::LocalPool.new(
  #     size: 5,
  #     timeout: 1,
  #     factory: RedisFactory.new("127.0.0.1".freeze)
  #   )
  #
  #   REDIS.with { |client| client.call("ping") }
  #
  # @note LocalPool is implemented in pure Ruby. It is not backed by the Rust
  #   native extension used by Counter, Map, and Queue. Its safety comes from
  #   Ruby Ractor locality: live resources are created and reused inside the
  #   Ractor that owns them.
  #
  # @see Pool Use Pool for plain mutable Ruby values where ownership transfer
  #   is the desired safety model.
  class LocalPool
    # Create a per-Ractor local pool facade.
    #
    # @param size [Integer] maximum number of resources in each Ractor-local pool
    # @param timeout [Numeric, nil] checkout timeout in seconds, or nil to wait indefinitely
    # @param factory [#call, nil] shareable object factory
    # @yieldreturn [Object] resource created inside the current Ractor
    # @raise [ArgumentError] if size, timeout, or factory is invalid
    # @raise [LocalJumpError] if no factory or block is given
    def initialize(size: 5, timeout: 1.0, factory: nil, &block)
      raise ArgumentError, "pool size must be positive" unless size.is_a?(Integer) && size.positive?
      raise ArgumentError, "pool timeout must be numeric or nil" unless timeout.nil? || timeout.is_a?(Numeric)
      raise ArgumentError, "pool timeout must be non-negative" if timeout && timeout.negative?
      raise ArgumentError, "use either factory: or block, not both" if factory && block

      factory ||= block
      raise LocalJumpError, "no factory given" unless factory
      raise ArgumentError, "factory must respond to #call" unless factory.respond_to?(:call)
      raise ArgumentError, "factory must be Ractor-shareable" unless Ractor.shareable?(factory)

      @size = size
      @timeout = timeout&.to_f
      @factory = factory
      @storage_key = :"ratomic_local_pool_#{object_id}"

      freeze
      Ractor.make_shareable(self)
    end

    # Checkout a current-Ractor-owned resource, yield it, then return it to the
    # same Ractor-local pool.
    #
    # No resource is moved between Ractors. The yielded object belongs to the
    # Ractor which called this method.
    #
    # @yieldparam object [Object] current-Ractor-owned resource
    # @raise [Ratomic::Error] if checkout times out
    # @return [Object] the block return value
    def with
      local_pool.with { |object| yield object }
    rescue Timeout::Error
      raise Ratomic::Error, "pool checkout timeout"
    end

    # Close the current Ractor's local pool, if it has been initialized.
    #
    # Other Ractors own independent local pools and are not affected. Available
    # resources are closed if they respond to #close. Resources currently
    # checked out by threads in this Ractor are closed when returned.
    #
    # @return [nil]
    def close
      pool = Ractor.current[@storage_key]
      return nil unless pool

      Ractor.current[@storage_key] = nil
      pool.close
      nil
    end

    # Minimal thread-safe resource pool used inside exactly one Ractor.
    class ResourcePool
      def initialize(size:, timeout:, factory:)
        @size = size
        @timeout = timeout
        @factory = factory
        @available = []
        @created = 0
        @closed = false
        @mutex = Mutex.new
        @condition = ConditionVariable.new
      end

      def with
        object = checkout
        yield object
      ensure
        checkin(object) if object
      end

      def close
        objects = nil

        @mutex.synchronize do
          @closed = true
          objects = @available.dup
          @available.clear
          @condition.broadcast
        end

        objects.each { |object| close_object(object) }
        nil
      end

      private

      def checkout
        deadline = monotonic_deadline

        should_create = @mutex.synchronize do
          raise IOError, "pool is closed" if @closed

          loop do
            object = @available.pop
            return object if object

            if @created < @size
              @created += 1
              break true
            end

            wait_for_available(deadline)
            raise IOError, "pool is closed" if @closed
          end
        end

        create_object if should_create
      end

      def checkin(object)
        close_now = false

        @mutex.synchronize do
          if @closed
            close_now = true
          else
            @available << object
            @condition.signal
          end
        end

        close_object(object) if close_now
        nil
      end

      def create_object
        @factory.call
      rescue Exception # rubocop:disable Lint/RescueException
        @mutex.synchronize do
          @created -= 1
          @condition.signal
        end
        raise
      end

      def close_object(object)
        object.close if object.respond_to?(:close)
      end

      def monotonic_deadline
        return nil unless @timeout

        Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      end

      def wait_for_available(deadline)
        if deadline
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Timeout::Error, "pool checkout timeout" if remaining <= 0

          @condition.wait(@mutex, remaining)
        else
          @condition.wait(@mutex)
        end
      end
    end

    private

    def local_pool
      Ractor.current[@storage_key] ||= ResourcePool.new(size: @size, timeout: @timeout, factory: @factory)
    end

    private_constant :ResourcePool
  end
end
