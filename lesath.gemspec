# frozen_string_literal: true

require_relative "lib/lesath/version"

Gem::Specification.new do |spec|
  spec.name = "lesath"
  spec.version = Lesath::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "Strict xlsx and ODS spreadsheet interchange"
  spec.description = "Reads and writes a documented, lossless subset of xlsx and ODS workbooks."
  spec.homepage = "https://github.com/noxdea/lesath"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt", "docs/adr/*.md"].select { |path| File.file?(path) } }
  spec.require_paths = ["lib"]
  spec.add_dependency "rexml", "~> 3.3"
  spec.add_dependency "rubyzip", "~> 3.0"
end
