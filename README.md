# Raven-Ruby

[![Build Status](https://secure.travis-ci.org/getsentry/raven-ruby.png?branch=master)](http://travis-ci.org/getsentry/raven-ruby)

A client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.

## Requirements

We test on Ruby 1.9.2, 1.9.3 and 2.0.0. Other versions/VMs are untested but we will accept pull requests to support them. Ruby 1.8 is not supported at this time.

## Installation

```ruby
gem "sentry-raven", :require => 'raven', :github => "getsentry/raven-ruby"
```

## Usage

You'll want to set your ```SENTRY_DSN``` environment variable to the URL on your project's API Keys setting page (e.g. ```https://secret:public@app.getsentry.com/9999```). For more information, see [Configuration](#configuration).

### Rails 3

In Rails 3, Sentry will "just work". 

### Rails 2

No support for Rails 2 yet, but it is being worked on.

### Rack

Add ```use Raven::Rack``` to your ```config.ru``` (or other rackup file). 

### Sinatra

Like any other Rack middleware, add ```use Raven::Rack``` to your Sinatra app.

## Capturing Events

Many implementations will automatically capture uncaught exceptions (such as Rails, Sidekiq or by using
the Rack middleware). Sometimes you may want to catch those exceptions, but still report on them.

Several helpers are available to assist with this.

### Capture Exceptions in a Block

```ruby
Raven.capture do
  # capture any exceptions which happen during execution of this block
  1 / 0
end
```

### Capture an Exception by Value

```ruby
begin
  1 / 0
rescue ZeroDivisionError => exception
  Raven.capture_exception(exception)
end
```

### Additional Context

Additional context can be passed to the capture methods.

```ruby
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
* `tags`: a mapping of [tags](https://www.getsentry.com/docs/tags/) describing this event
* `extra`: a mapping of arbitrary context

## Testing

```bash
$ bundle install
$ rake spec
```

## Configuration

### SENTRY_DSN

After you complete setting up a project, you'll be given a value which we call a DSN, or Data Source Name. It looks a lot like a standard URL, but it's actually just a representation of the configuration required by Raven (the Sentry client). It consists of a few pieces, including the protocol, public and secret keys, the server address, and the project identifier.

With Raven, you may either set the ```SENTRY_DSN``` environment variable (recommended), or set your DSN manually in a config block:

```ruby
Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
end
```

### Environments

By default events will be sent to Sentry in all environments except 'test'.

You can configure Raven to run only in certain environments by configuring the `environments` whitelist:

```ruby
Raven.configure do |config|
  config.environments = %w[ production ]
end
```

Sentry automatically sets the current environment to ```RAILS_ENV```, or if it is not present, ```RACK_ENV```. If you are using Sentry outside of Rack or Rails, you'll need to set the current environment yourself:

```ruby
Raven.configure do |config|
  config.current_environment = 'my_cool_environment'
end
```

### Excluding Exceptions

If you never wish to be notified of certain exceptions, specify 'excluded_exceptions' in your config file.

In the example below, the exceptions Rails uses to generate 404 responses will be suppressed.

```ruby
Raven.configure do |config|
  config.excluded_exceptions = ['ActionController::RoutingError', 'ActiveRecord::RecordNotFound']
end
```

## Sanitizing Data (Processors)

If you need to sanitize or pre-process (before its sent to the server) data, you can do so using the Processors
implementation. By default, a single processor is installed (Raven::Processor::SanitizeData), which will attempt to
sanitize keys that match various patterns (e.g. password) and values that resemble credit card numbers.

To specify your own (or to remove the defaults), simply pass them with your configuration:

```ruby
Raven.configure do |config|
  config.processors = [Raven::Processor::SanitizeData]
end
```

## Command Line Interface

Raven includes a basic CLI for testing your DSN:

```ruby
ruby -Ilib ./bin/raven test <DSN>
```

Resources
---------

* [Bug Tracker](http://github.com/getsentry/raven-ruby/issues>)
* [Code](http://github.com/getsentry/raven-ruby>)
* [Mailing List](https://groups.google.com/group/getsentry>)
* [IRC](irc://irc.freenode.net/sentry>)  (irc.freenode.net, #sentry)
