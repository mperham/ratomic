# frozen_string_literal: true

require "ratomic/ratomic"
require "ratomic/version"

module Ratomic
  class Error < StandardError; end
end

require "ratomic/undefined"
require "ratomic/counter"
require "ratomic/map"
require "ratomic/queue"
require "ratomic/pool"
