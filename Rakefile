# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rake/extensiontask"
require "standard/rake"

GEMSPEC = Gem::Specification.load("ratomic.gemspec")
Rake::ExtensionTask.new("ratomic", GEMSPEC) do |task|
  task.lib_dir = "lib/ratomic"
end
Minitest::TestTask.create

task :rust do
  `make rust`
end

task default: %i[clean clobber rust compile test build]
