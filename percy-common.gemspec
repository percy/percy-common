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

  # Pinned as we rely on `time_since` which was taken out after this version.
  spec.add_dependency 'dogstatsd-ruby', '4.3.0'

  spec.add_dependency 'excon', '~> 0.57'

  spec.add_development_dependency 'bundler', '~> 1.15'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.2'
  spec.add_development_dependency 'guard-rspec', '~> 4.7'
  spec.add_development_dependency 'percy-style'
end
