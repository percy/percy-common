lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'percy/common/version'

Gem::Specification.new do |spec|
  spec.name          = 'percy-common'
  spec.version       = Percy::Common::VERSION
  spec.authors       = ['Perceptual Inc.']
  spec.email         = ['team@percy.io']

  spec.summary       = 'Server-side common library for Percy.'
  spec.description   = ''
  spec.homepage      = ''

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(/^(test|spec|features)\//)
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'dogstatsd-ruby', '>= 4.4', '< 4.9'
  spec.add_dependency 'excon', '~> 0.57'
  spec.add_dependency 'redis', '>= 4.1.3', '< 5.0.0'

  spec.add_development_dependency 'bundler', '~> 2.2.7'
  spec.add_development_dependency 'guard-rspec', '~> 4.7'
  spec.add_development_dependency 'percy-style', '~> 0.7.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.2'
end
