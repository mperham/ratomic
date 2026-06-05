# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "support/simplecov" unless defined?(SimpleCov)

require "ratomic"

require "minitest/autorun"
require "timeout"

module RactorTestHelpers
  RACTOR_TIMEOUT = 10

  def ractor_value(ractor, timeout: RACTOR_TIMEOUT)
    Timeout.timeout(timeout, "Ractor did not finish within #{timeout} seconds") do
      ractor.join if ractor.respond_to?(:join)
      ractor.value
    end
  end

  def poll_ractor_value(ractor, attempts: 50, delay: 0.01)
    result = nil
    attempts.times do
      result = ractor_value(ractor)
      break if result
    rescue Ractor::Error
      sleep delay
    end
    result
  end
end

Minitest::Test.include(RactorTestHelpers)
