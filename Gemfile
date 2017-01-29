source "https://rubygems.org/"

gemspec

group :test do
  gem "rack"
  gem "sidekiq"
end

group :development do
  gem "pry"
  gem "pry-coolline"
  gem "benchmark-ips"
  gem "benchmark-ipsa"
  if RUBY_VERSION > '2.4'
    gem "yajl-ruby", :git => 'https://github.com/brianmario/yajl-ruby.git', :ref => '6f39ff8c3611edbf4edca1d0cc3ddc15aa5e4e92'
  else
    gem "yajl-ruby", :platforms => :mri
  end
end

group :test, :development do
  gem "json", ">= 2" if RUBY_VERSION > '2.4'
end
