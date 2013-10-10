# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'darius/version'

Gem::Specification.new do |spec|
  spec.name          = "darius"
  spec.version       = Darius::VERSION
  spec.authors       = ["Stephen Zhang"]
  spec.email         = ["stephen.zsy@gmail.com"]
  spec.description   = 'Codename: Darius'
  spec.summary       = 'Codename: Darius'
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = Dir['lib/**/*.rb'] + Dir['bin/*']
  spec.files         += Dir['test/**/*']
  spec.files.reject! { |fn| fn.include? '.git' }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"

  spec.add_runtime_dependency 'rack'
  spec.add_runtime_dependency 'thin'
  spec.add_runtime_dependency 'nokogiri'
  spec.add_runtime_dependency 'aws-sdk', '>= 1.21.0'
  spec.add_runtime_dependency 'thrift'
  spec.add_runtime_dependency 'activesupport'

end
