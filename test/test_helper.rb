# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ratomic"

require "minitest/autorun"

module RactorTestHelpers
  def ractor_value(ractor)
    ractor.join if ractor.respond_to?(:join)
    ractor.value
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
