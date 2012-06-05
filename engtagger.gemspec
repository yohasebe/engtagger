# -*- encoding: utf-8 -*-
require File.expand_path('../lib/engtagger/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Yoichiro Hasebe"]
  gem.email         = ["yohasebe@gmail.com"]
  gem.summary         = %q{A probability based, corpus-trained English POS tagger}  
  gem.description     = %q{A Ruby port of Perl Lingua::EN::Tagger, a probability based, corpus-trained tagger that assigns POS tags to English text based on a lookup dictionary and a set of probability values.}  
  gem.homepage        = "http://github.com/yohasebe/engtagger"  

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "engtagger"
  gem.require_paths = ["lib"]
  gem.version       = EngTagger::VERSION  
end
