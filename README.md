# Raven-Ruby

[![Build Status](https://secure.travis-ci.org/coderanger/raven-ruby.png?branch=master)](http://travis-ci.org/coderanger/raven-ruby)

A client and integration layer for the [Sentry](https://github.com/dcramer/sentry) error reporting API.

This library is still forming, so if you are looking to just use it, please check back in a few weeks.

## Installation

Add the following to your `Gemfile`:

```ruby
gem "sentry-raven", :git => "https://github.com/coderanger/raven-ruby.git"
```

Or install manually
```bash
$ gem install sentry-raven
```

## Usage

### Rails 3

Add a `config/initializers/raven.rb` containing:

```ruby
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
end
```

### Rails 2

No support for Rails 2 yet.

### Other Rack Servers

Basic RackUp file.

```ruby
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
end

use Raven::Rack
```

### Other Ruby

```ruby
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'

  # manually configure environment if ENV['RACK_ENV'] is not defined
  config.current_environment = 'production'
end

Raven.capture # Global style

Raven.capture do # Block style
  ...
end
```

## Testing

```bash
$ bundle install
$ rake spec
```

## Notifications in development mode

By default events will only be sent to Sentry if your application is running in a production environment. This is configured by default if you are running a Rack application (i.e. anytime `ENV['RACK_ENV']` is set).

You can configure Raven to run in non-production environments by configuring the `environments` whitelist:

```ruby
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
  config.environments = %w[ development production ]
end
```