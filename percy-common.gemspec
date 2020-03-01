# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'percy/common/version'

Gem::Specification.new do |spec|
  spec.name          = 'percy-common'
  spec.version       = Percy::Common::VERSION
  spec.authors       = ['Perceptual Inc.']
  spec.email         = ['team@percy.io']

  spec.summary       = %q{Server-side common library for Percy.}
  spec.description   = %q{}
  spec.homepage      = ''

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.require_paths = ['lib']

  spec.add_dependency 'dogstatsd-ruby', '>= 4.4', '< 4.8'
  spec.add_dependency 'excon', '~> 0.57'

  spec.add_development_dependency 'bundler', '~> 2.0.2'
  spec.add_development_dependency 'rake', '~> 12.3'
  spec.add_development_dependency 'rspec', '~> 3.2'
  spec.add_development_dependency 'guard-rspec', '~> 4.7'
  spec.add_development_dependency 'percy-style', '~> 0.6.0'
end
