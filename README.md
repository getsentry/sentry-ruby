# Raven-Ruby

[![Build Status](https://secure.travis-ci.org/getsentry/raven-ruby.png?branch=master)](http://travis-ci.org/getsentry/raven-ruby)

A client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.

This library is still forming, so if you are looking to just use it, please check back in a few weeks.

## Installation

Add the following to your `Gemfile`:

```ruby
gem "sentry-raven", :git => "https://github.com/getsentry/raven-ruby.git"
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

### Rack

Basic RackUp file.

```ruby
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
end

use Raven::Rack
```

### Sinatra

```ruby
require 'sinatra'
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
end

use Raven::Rack

get '/' do
  1 / 0
end
```

### Other Ruby

```ruby
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'

  # manually configure environment if ENV['RACK_ENV'] is not defined
  config.current_environment = 'production'
end


## Capturing Events

Many implementations will automatically capture uncaught exceptions (such as Rails, or by using
the Rack middleware). Sometimes you may want to catch those exceptions, but still report on them.

Several helps are available to assist with this.

### Capture Exceptions in a Block

```
Raven.capture do
  # capture any exceptions which happen during execution of this block
  1 / 0
end
```

### Capture an Exception by Value

```
begin
  1 / 0
rescue ZeroDivisionError => exception
  Raven.capture_exception(exception)
end
```

### Additional Context

Additional context can be passed to the capture methods.

```
Raven.capture_message("My event", {
  :logger => 'logger',
  :extra => {
    'my_custom_variable' => 'value'
  },
  :tags => {
    'environment' => 'production',
  }
})
```

The following attributes are available:

* `logger`: the logger name to record this event under
* `level`: a string representing the level of this event (fatal, error, warning, info, debug)
* `server_name`: the hostname of the server
* `tags`: a mapping of tags describing this event
* `extra`: a mapping of arbitrary context

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

## Excluding Exceptions

If you never wish to be notified of certain exceptions, specify 'excluded_exceptions' in your config file.

In the example below, the exceptions Rails uses to generate 404 responses will be suppressed.

```ruby
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
  config.excluded_exceptions = ['ActionController::RoutingError', 'ActiveRecord::RecordNotFound']
end
```

## Sanitizing Data (Processors)

If you need to sanitize or pre-process (before its sent to the server) data, you can do so using the Processors
implementation. By default, a single processor is installed (Raven::Processors::SanitizeData), which will attempt to
sanitize keys that match various patterns (e.g. password) and values that resemble credit card numbers.

To specify your own (or to remove the defaults), simply pass them with your configuration:

```ruby
require 'raven'

Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
  config.processors = [Raven::Processors::SanitizeData]
end
```

Resources
---------

* [Bug Tracker](http://github.com/getsentry/raven-ruby/issues>)
* [Code](http://github.com/getsentry/raven-ruby>)
* [Mailing List](https://groups.google.com/group/getsentry>)
* [IRC](irc://irc.freenode.net/sentry>)  (irc.freenode.net, #sentry)
