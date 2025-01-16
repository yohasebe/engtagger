# frozen_string_literal: true

require_relative "lib/engtagger/version"

Gem::Specification.new do |gem|
  gem.authors       = ["Yoichiro Hasebe"]
  gem.email         = ["yohasebe@gmail.com"]
  gem.summary       = "A probability based, corpus-trained English POS tagger"
  gem.description   = "A Ruby port of Perl Lingua::EN::Tagger, a probability based, corpus-trained tagger that assigns POS tags to English text based on a lookup dictionary and a set of probability values."
  gem.homepage      = "http://github.com/yohasebe/engtagger"
  gem.license       = "GPL"
  gem.required_ruby_version = Gem::Requirement.new(">= 2.6")
  gem.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "engtagger"
  gem.require_paths = ["lib"]
  gem.version       = EngTagger::VERSION
  gem.add_dependency "sin_lru_redux"
end
