# frozen_string_literal: true

require_relative "lib/engtagger/version"

Gem::Specification.new do |gem|
  gem.authors       = ["Yoichiro Hasebe"]
  gem.email         = ["yohasebe@gmail.com"]
  gem.summary       = "A corpus-trained English POS tagger in pure Ruby"
  gem.description   = "An English part-of-speech tagger with a bundled averaged-perceptron model and no runtime dependencies. Tags text and extracts nouns and noun phrases, with the methods of the 0.4 line."
  gem.homepage      = "https://github.com/yohasebe/engtagger"
  gem.license       = "GPL-3.0-only"
  gem.required_ruby_version = Gem::Requirement.new(">= 3.0")
  # Ship only what the library needs at runtime plus its legal/user documents;
  # development files (Gemfile, Rakefile, dotfiles, tests, tools, docs) stay
  # out of the package.
  gem.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").select do |f|
      f.start_with?("lib/") || %w[LICENSE NOTICE README.md CHANGELOG.md].include?(f)
    end
  end
  gem.name          = "engtagger"
  gem.require_paths = ["lib"]
  gem.version       = EngTagger::VERSION
  gem.metadata      = {
    "source_code_uri" => "https://github.com/yohasebe/engtagger",
    "changelog_uri" => "https://github.com/yohasebe/engtagger/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/yohasebe/engtagger/issues"
  }
  gem.post_install_message = <<~MESSAGE
    EngTagger 2.0 is a rewrite: an averaged-perceptron model replaces the
    classic HMM. Tagging and extraction methods keep their names, but tagging
    output differs (it got more accurate) and Ruby >= 3.0 is required.

    For the previous engine and its exact output:  gem "engtagger", "~> 0.4"
  MESSAGE
end
