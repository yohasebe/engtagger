# frozen_string_literal: true

require_relative "lib/engtagger/version"

Gem::Specification.new do |gem|
  gem.authors       = ["Yoichiro Hasebe"]
  gem.email         = ["yohasebe@gmail.com"]
  gem.summary       = "A probability based, corpus-trained English POS tagger"
  gem.description   = "A Ruby port of Perl Lingua::EN::Tagger, a probability based, corpus-trained tagger that assigns POS tags to English text based on a lookup dictionary and a set of probability values."
  gem.homepage      = "https://github.com/yohasebe/engtagger"
  gem.license       = "GPL-3.0-only"
  gem.required_ruby_version = Gem::Requirement.new(">= 2.6")
  gem.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features|tools|docs)/}) }
  end
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.name          = "engtagger"
  gem.metadata      = {
    "source_code_uri" => "https://github.com/yohasebe/engtagger",
    "changelog_uri" => "https://github.com/yohasebe/engtagger/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/yohasebe/engtagger/issues"
  }
  gem.require_paths = ["lib"]
  gem.version       = EngTagger::VERSION
  gem.add_dependency "sin_lru_redux"
  gem.post_install_message = <<~MESSAGE
    EngTagger 0.4.5 is the final planned release of the 0.4 line.

    Version 2.0 replaces the HMM engine with an averaged perceptron trained on
    openly licensed data. It is considerably more accurate, and its tagging
    output differs, so treat it as a rewrite rather than an upgrade.

    To stay on this line, pin it:  gem "engtagger", "~> 0.4"
  MESSAGE
end
