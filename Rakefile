require 'rubygems'
require 'bundler/setup'
require 'rake'
require 'raven'
require 'rubygems/package_task'
require 'bundler/gem_tasks'

gemspec = Gem::Specification.load(Dir['*.gemspec'].first)

Gem::PackageTask.new(gemspec).define

begin
  require 'rspec/core/rake_task'
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:rubocop)
  RSpec::Core::RakeTask.new(:spec) do |spec|
    spec.pattern = 'spec/**/*_spec.rb'
  end

rescue LoadError
  task :spec do
    abort "Rspec is not available. bundle install to run unit tests"
  end
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.warning = true
  test.pattern = 'test/**/test_*.rb'
end

task :default => [:rubocop, :test, :spec]
