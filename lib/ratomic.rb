# frozen_string_literal: true

require "timeout"

require_relative "ratomic/version"
require_relative "ratomic/ratomic"
require_relative "ratomic/counter"
require_relative "ratomic/undefined"
require_relative "ratomic/pool"
require_relative "ratomic/map"
require_relative "ratomic/queue"

module Ratomic
  # Base error for Ratomic-specific runtime failures.
  class Error < StandardError; end
end
