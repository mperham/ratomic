# frozen_string_literal: true

require "timeout"

module Ratomic
  # A Ractor-safe ownership-transfer pool for mutable Ruby objects.
  #
  # Pool follows a Rust-inspired ownership-transfer model: a pooled object has
  # one active owner at a time. #checkout moves ownership from the pool to the
  # caller; #checkin moves ownership back to the pool. Ruby enforces stale
  # caller references dynamically with Ractor::MovedError.
  #
  # This is ownership transfer, not borrowing. Pool never lends shared mutable
  # references across Ractors.
  #
  # Pool uses a private coordinator Ractor and caller-owned Ractor::Port reply
  # ports. Objects are moved to callers on checkout and moved back to the pool
  # on checkin. This is intentionally different from sharing the same mutable
  # object between Ractors: at any instant, exactly one Ractor owns a checked-out
  # object.
  #
  # @example Reuse mutable buffers safely
  #   BUFFERS = Ratomic::Pool.new(4, 1.0) { [] }
  #   BUFFERS.with do |buffer|
  #     buffer.clear
  #     buffer << :change
  #   end
  class Pool
    # Create a pool and seed it with +size+ objects from the factory block.
    #
    # @param size [Integer] number of pooled objects
    # @param timeout [Numeric, nil] checkout timeout in seconds, or nil to wait indefinitely
    # @yieldreturn [Object] mutable object to store in the pool
    # @raise [ArgumentError] if +size+ is not positive
    # @raise [LocalJumpError] if no factory block is given
    def initialize(size = 5, timeout = 1.0)
      raise ArgumentError, "pool size must be positive" if size <= 0
      raise LocalJumpError, "no block given" unless block_given?

      @timeout = timeout&.to_f
      @control = self.class.send(:new_control_ractor)
      size.times { @control.send([:checkin, yield], move: true) }
      freeze
      Ractor.make_shareable(self)
    end

    # Checkout one object from the pool.
    #
    # The returned object has been moved from the pool to the caller. The caller
    # owns it until it is passed to #checkin.
    #
    # @return [Object, nil] pooled object, or nil after timeout
    def checkout
      reply = Ractor::Port.new
      request_id = reply.object_id
      @control << [:checkout, request_id, reply]
      receive_checkout_reply(reply)
    rescue Timeout::Error
      nil
    ensure
      @control << [:cancel, request_id] if request_id
      reply&.close unless reply&.closed?
    end

    # Return an object to the pool.
    #
    # This moves ownership from the caller back to the pool. The caller must not
    # use the object after calling this method; Ruby raises Ractor::MovedError
    # for stale references.
    #
    # @param object [Object] previously checked-out pooled object
    # @return [nil]
    def checkin(object)
      @control.send([:checkin, object], move: true)
      nil
    end

    # Stop the private coordinator Ractor.
    #
    # This is primarily useful for tests and short-lived scripts. A closed pool
    # should not be used for further checkout/checkin operations.
    #
    # @return [nil]
    def close
      @control << [:shutdown]
      @control.value
      nil
    rescue Ractor::ClosedError, Ractor::Error
      nil
    end

    # Checkout an object, yield it, then move it back to the pool.
    #
    # This is the preferred API because it guarantees checkin through an ensure
    # block. If checkout times out, raises Ratomic::Error and does not yield.
    #
    # @yieldparam object [Object] checked-out pooled object
    # @raise [Ratomic::Error] if checkout times out
    # @return [Object] block return value
    def with
      object = checkout
      raise Ratomic::Error, "pool checkout timeout" if object.nil?

      yield object
    ensure
      checkin(object) unless object.nil?
    end

    def self.new_control_ractor
      Ractor.new { Ratomic::Pool.send(:run_control_loop) }
    end
    private_class_method :new_control_ractor

    def self.run_control_loop
      available = []
      waiting = {}

      loop do
        command, *args = Ractor.receive
        break if handle_command(command, args, available, waiting) == :shutdown
      end
    end
    private_class_method :run_control_loop

    def self.handle_command(command, args, available, waiting)
      case command
      when :checkout
        handle_checkout(args, available, waiting)
      when :checkin
        handle_checkin(args.fetch(0), available, waiting)
      when :cancel
        waiting.delete(args.fetch(0))
      when :shutdown
        :shutdown
      end
    end
    private_class_method :handle_command

    def self.handle_checkout(args, available, waiting)
      request_id, reply = args
      if (object = available.shift)
        reply.send(object, move: true)
      else
        waiting[request_id] = reply
      end
    end
    private_class_method :handle_checkout

    def self.handle_checkin(object, available, waiting)
      loop do
        _request_id, reply = waiting.shift
        return available << object if reply.nil?

        begin
          reply.send(object, move: true)
          return
        rescue Ractor::ClosedError
          next
        end
      end
    end
    private_class_method :handle_checkin

    private

    def receive_checkout_reply(reply)
      return reply.receive unless @timeout

      Timeout.timeout(@timeout) { reply.receive }
    end
  end
end
