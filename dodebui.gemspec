# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dodebui/version'

desc =  'Docker Debian builder (DoDeBui): '
desc += 'Builds debian packages in Docker containers'

Gem::Specification.new do |spec|
  spec.name          = 'dodebui'
  spec.version       = Dodebui::VERSION
  spec.authors       = ['Christian Simon']
  spec.email         = ['simon@swine.de']
  spec.summary       = desc
  spec.description   = desc
  spec.homepage      = 'https://github.com/simonswine/dodebui'
  spec.license       = 'GPLv3'
  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'docker-api'
  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rubocop', '~> 0.30'
end
