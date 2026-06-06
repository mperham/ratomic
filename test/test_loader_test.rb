# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

require_relative "test_helper"

class TestLoader < Minitest::Test
  def test_require_ratomic_works_with_versioned_extension_layout
    Dir.mktmpdir do |dir|
      stdout, stderr, status = run_loader_probe(prepare_install_tree(dir))
      assert_predicate status, :success?, stderr
      assert_equal Ratomic::VERSION, stdout.strip
    end
  end

  private

  def prepare_install_tree(dir) # rubocop:disable Metrics/AbcSize
    native_extension = built_native_extension
    assert native_extension, "expected a built native extension in lib/ratomic"

    lib_dir = File.join(dir, "lib")
    ratomic_dir = File.join(lib_dir, "ratomic")
    ruby_api_ver = RbConfig::CONFIG.fetch("ruby_version").split(".", 3)[0, 2].join(".")
    version_dir = File.join(ratomic_dir, ruby_api_ver)

    FileUtils.mkdir_p(version_dir)
    FileUtils.cp(Dir[File.expand_path("../lib/ratomic/*.rb", __dir__)], ratomic_dir)
    FileUtils.cp(File.expand_path("../lib/ratomic.rb", __dir__), lib_dir)
    FileUtils.cp(native_extension, File.join(version_dir, File.basename(native_extension)))

    lib_dir
  end

  def built_native_extension
    Dir[File.expand_path("../lib/ratomic/*/ratomic.{so,bundle}", __dir__)].first
  end

  def run_loader_probe(lib_dir)
    Open3.capture3(
      RbConfig.ruby,
      "-I",
      lib_dir,
      "-e",
      'require "ratomic"; puts Ratomic::VERSION'
    )
  end
end
