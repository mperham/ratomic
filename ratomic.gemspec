# frozen_string_literal: true

require_relative "lib/ratomic/version"

Gem::Specification.new do |spec|
  spec.name = "ratomic"
  spec.version = Ratomic::VERSION
  spec.authors = ["Mike Perham", "Ken C. Demanawa"]
  spec.email = ["mike@perham.net"]
  spec.metadata["maintainers"] = "Ken C. Demanawa"

  spec.summary = "Mutable data structures for Ractors"
  spec.description = spec.summary
  spec.homepage = "https://github.com/mperham/ratomic"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mperham/ratomic"
  spec.metadata["changelog_uri"] = "https://github.com/mperham/ratomic"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = [
    "Cargo.lock",
    "Cargo.toml",
    "CHANGELOG.md",
    "LICENSE.txt",
    "README.md",
    "ratomic.gemspec"
  ] + Dir[
    "lib/**/*.rb",
    "ext/ratomic/Cargo.toml",
    "ext/ratomic/build.rs",
    "ext/ratomic/extconf.rb",
    "ext/ratomic/src/**/*.rs"
  ]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/ratomic/extconf.rb"]

  spec.add_dependency "rb_sys", "~> 0.9.128"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
