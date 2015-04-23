# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "qs/version"

Gem::Specification.new do |gem|
  gem.name        = "qs"
  gem.version     = Qs::VERSION
  gem.authors     = ["Kelly Redding", "Collin Redding"]
  gem.email       = ["kelly@kellyredding.com", "collin.redding@me.com"]
  gem.description = %q{Define message queues. Process jobs and events. Profit.}
  gem.summary     = %q{Define message queues. Process jobs and events. Profit.}
  gem.homepage    = "http://github.com/redding/qs"
  gem.license     = 'MIT'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency("dat-worker-pool", ["~> 0.5"])
  gem.add_dependency("hella-redis",     ["~> 0.2"])
  gem.add_dependency("ns-options",      ["~> 1.1"])
  gem.add_dependency("SystemTimer",     ["~> 1.2"])

  gem.add_development_dependency("assert", ["~> 2.14"])
  gem.add_development_dependency("scmd",   ["~> 2.3"])
end
