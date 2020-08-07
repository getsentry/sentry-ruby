source "https://rubygems.org/"

gemspec

gem "rails", "< 6"
gem "rspec-rails", "> 3"

gem "benchmark-ips"
gem "benchmark-ipsa"
gem "ruby-prof", platform: :mri

instance_eval File.read(File.join(File.dirname(__FILE__), "gemfiles", "Gemfile.base"))
