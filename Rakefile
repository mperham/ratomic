# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rake/clean"
require "rb_sys/extensiontask"
require "rbconfig"

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError => e
  task(:rubocop) { raise e }
end

begin
  require "yard"
  YARD::Rake::YardocTask.new(:yard)
rescue LoadError => e
  task(:yard) { raise e }
end

GEMSPEC = Gem::Specification.load("ratomic.gemspec")
RUBY_VERSION_REQUIREMENT = "4.0"
RUBY_ABI_VERSION = RbConfig::CONFIG.fetch("ruby_version").split(".", 3)[0, 2].join(".")
CROSS_PLATFORMS = %w[
  x86_64-linux
  aarch64-linux
  x86_64-darwin
  arm64-darwin
  x64-mingw-ucrt
].freeze

RbSys::ExtensionTask.new("ratomic", GEMSPEC) do |ext|
  ext.lib_dir = "lib/ratomic/#{RUBY_ABI_VERSION}"
  ext.cross_compile = true
  ext.cross_platform = [ENV.fetch("RUBY_TARGET", nil)].compact
end
[
  "lib/ratomic/ratomic.so",
  "lib/ratomic/#{RUBY_ABI_VERSION}/ratomic.so"
].each { |path| CLEAN.include(path) }
Minitest::TestTask.create do |task|
  task.test_prelude = %(require "support/simplecov")
end

task build: :compile

namespace :rbs do
  desc "Validate the curated RBS signatures"
  task :validate do
    sh("bundle", "exec", "rbs", "validate", "sig/ratomic.rbs")
  end
end

namespace :gem do
  task :native_current do
    platform = ENV.fetch("RUBY_TARGET")
    gem_file = "pkg/#{GEMSPEC.name}-#{GEMSPEC.version}-#{platform}.gem"
    stage_path = "tmp/#{platform}/stage"

    Rake::Task["native:#{platform}"].invoke

    spec = GEMSPEC.dup
    spec.platform = Gem::Platform.new(platform)
    spec.extensions.clear
    spec.dependencies.reject! { |dependency| dependency.name == "rb_sys" }
    spec.files = Dir.chdir(stage_path) do
      Dir[
        "CHANGELOG.md",
        "LICENSE.txt",
        "README.md",
        "lib/**/*.rb",
        "lib/ratomic/**/*.{bundle,dll,so}",
        "ratomic.gemspec"
      ]
    end
    spec.required_ruby_version = [">= 4.0", "< 4.1.dev"]

    mkdir_p("pkg")
    rm_f(gem_file)
    root = Dir.pwd
    Dir.chdir(stage_path) do
      built_gem = Gem::Package.build(spec, false, false, File.basename(gem_file))
      mv(built_gem, File.join(root, gem_file))
    end
  end

  desc "Build source and native gems for the supported release platforms"
  task :native do
    rm_rf("pkg")
    Rake::Task["build"].invoke

    CROSS_PLATFORMS.each do |platform|
      sh(
        "bundle",
        "exec",
        "rb-sys-dock",
        "--platform",
        platform,
        "--ruby-versions",
        RUBY_VERSION_REQUIREMENT,
        "--",
        "sh",
        "-lc",
        "bundle install && bundle exec rake gem:native_current"
      )
    end
  end
end

task default: %i[clean compile test]
