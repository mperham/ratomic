# frozen_string_literal: true

require "simplecov"

SimpleCov.command_name "Minitest"
SimpleCov.use_merging false
SimpleCov.start do
  add_filter "/test/"
  add_filter "/tmp/"

  enable_coverage :branch

  add_group "Public API", "lib/ratomic"
end
