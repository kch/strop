# frozen_string_literal: true

require_relative "lib/strop/version"

Gem::Specification.new do |s|
  s.name        = "strop"
  s.version     = Strop::VERSION
  s.summary     = "Command-line option parser"
  s.description = "Build options from parsing help text, with pattern matching for result processing"
  s.authors     = ["Caio Chassot"]
  s.email       = "dev@caiochassot.com"
  s.homepage    = "http://github.com/kch/strop"
  s.license     = "MIT"

  s.files = %w[
    MIT-LICENSE
    README.md
    lib/strop.rb
    lib/strop/version.rb
  ]
  s.require_paths = ["lib"]

  s.required_ruby_version = ">= 3.3"

  s.metadata = {
    "homepage_uri"      => s.homepage,
    "source_code_uri"   => s.homepage,
    "bug_tracker_uri"   => "#{s.homepage}/issues",
    "documentation_uri" => "https://rubydoc.info/gems/#{s.name}"
  }
end
