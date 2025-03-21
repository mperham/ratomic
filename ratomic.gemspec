# frozen_string_literal: true

require_relative "lib/ratomic/version"

Gem::Specification.new do |spec|
  spec.name = "ratomic"
  spec.version = Ratomic::VERSION
  spec.authors = ["Mike Perham"]
  spec.email = ["mike@perham.net"]

  spec.summary = "Mutable data structures for Ractors"
  spec.description = spec.summary
  spec.homepage = "https://github.com/mperham/ratomic"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mperham/ratomic"
  spec.metadata["changelog_uri"] = "https://github.com/mperham/ratomic"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      (f == gemspec) || f.start_with?(*%w[lib/ ext/])
    end
  end
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/ratomic/extconf.rb"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
