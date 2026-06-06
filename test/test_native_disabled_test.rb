# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

require_relative "test_helper"

class TestNativeDisabled < Minitest::Test
  def test_require_ratomic_without_native_extension_loads_pure_ruby_surface
    Dir.mktmpdir do |dir|
      lib_dir = prepare_source_tree_without_native_extension(dir)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        "-I",
        lib_dir,
        "-e",
        <<~RUBY
          require "ratomic"
          puts Ratomic.native_enabled?
          puts Ratomic::VERSION
          puts Ratomic::Undefined
          puts Ratomic::Pool
        RUBY
      )

      assert_predicate status, :success?, stderr
      assert_equal "false\n#{Ratomic::VERSION}\nRatomic::Undefined\nRatomic::Pool\n", stdout
    end
  end

  private

  def prepare_source_tree_without_native_extension(dir)
    lib_dir = File.join(dir, "lib")
    ratomic_dir = File.join(lib_dir, "ratomic")

    FileUtils.mkdir_p(ratomic_dir)
    FileUtils.cp(Dir[File.expand_path("../lib/ratomic/*.rb", __dir__)], ratomic_dir)
    FileUtils.cp(File.expand_path("../lib/ratomic.rb", __dir__), lib_dir)

    lib_dir
  end
end
