require 'rake'
require 'raven'
require 'rubygems/package_task'

gemspec = Gem::Specification.load(Dir['*.gemspec'].first)

Gem::PackageTask.new(gemspec).define

begin
  require 'rubygems'
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec) do |spec|
    spec.pattern = 'spec/**/*_spec.rb'
  end

rescue LoadError
  task :spec do
    abort "Rspec is not available. bundle install to run unit tests"
  end
end

task :default => :spec
