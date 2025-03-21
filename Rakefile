# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rake/extensiontask"
require "standard/rake"

task build: :compile

GEMSPEC = Gem::Specification.load("ratomic.gemspec")
Rake::ExtensionTask.new("ratomic", GEMSPEC) do |ext|
  ext.lib_dir = "lib/ratomic"
end

task default: %i[clobber compile]

Minitest::TestTask.create

task default: %i[build test standard]
