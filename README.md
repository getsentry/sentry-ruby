# Raven-Ruby

[![Gem Version](https://img.shields.io/gem/v/sentry-raven.svg)](https://rubygems.org/gems/sentry-raven)
[![Build Status](https://img.shields.io/travis/getsentry/raven-ruby/master.svg)](https://travis-ci.org/getsentry/raven-ruby)
[![Coverage Status](https://img.shields.io/coveralls/getsentry/raven-ruby/master.svg)](https://coveralls.io/r/getsentry/raven-ruby)

A client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.

## Requirements

We test on Ruby MRI 1.8.7, 1.9.3 and 2.0.0. Rubinius and JRuby support is experimental.

## Installation

```ruby
gem "sentry-raven" #, :github => "getsentry/raven-ruby"
```

## Usage

The minimum configuration require setting the ``SENTRY_DSN`` with value found on your Sentry project settings page. It should resemble something like ```https://public:secret@app.getsentry.com/9999```. See [Configuration](#configuration) for configuration methods, and other options.

Many implementations will automatically capture uncaught exceptions (such as Rails, Sidekiq or by using
the Rack middleware). If you catch those exceptions yourself, but still want to report on them, see section [Capturing Events](#capturing-events).

### Rails 3 or 4

In Rails 3 or 4 all uncaught exceptions will be automatically reported under most situations.

You'll still want to ensure you've disabled anything that would prevent errors from being propagated to the ```Raven::Rack``` middleware:

Disable ```ActionDispatch::ShowExceptions```:

```ruby
config.action_dispatch.show_exceptions = false
```

#### Delayed::Job

No extra configuration required. Usage of [delayed-plugins-raven](https://github.com/qiushihe/delayed-plugins-raven) gem is deprecated.

### Rails 2

No support for Rails 2 yet, but it is being worked on.

### Rack

Add ```use Raven::Rack``` to your ```config.ru``` (or other rackup file).

### Sinatra

Like any other Rack middleware, add ```use Raven::Rack``` to your Sinatra app.

### Sidekiq

Raven includes [Sidekiq middleware](https://github.com/mperham/sidekiq/wiki/Middleware) which takes
care of reporting errors that occur in Sidekiq jobs. To use it, just require the middleware by doing

```ruby
require 'raven/sidekiq'
```
after you require Sidekiq. If you are using Sidekiq with Rails, just put this require somewhere in the initializers.


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
Raven.capture_message "My event",
  logger: 'logger',
  extra: {
    my_custom_variable: 'value'
  },
  tags: {
    environment: 'production'
  }
```

The following attributes are available:

* `logger`: the logger name to record this event under
* `level`: a string representing the level of this event (fatal, error, warning, info, debug)
* `server_name`: the hostname of the server
* `tags`: a mapping of [tags](https://www.getsentry.com/docs/tags/) describing this event
* `extra`: a mapping of arbitrary context

## Providing Request Context

Most of the time you're not actually calling out to Raven directly, but you still want to provide some additional context. This lifecycle generally constists of something like the following:

- Set some context via a middleware (e.g. the logged in user)
- Send all given context with any events during the request lifecycle
- Cleanup context

There are three primary methods for providing request context:

```ruby
# bind the logged in user
Raven.user_context email: 'foo@example.com'

# tag the request with something interesting
Raven.tags_context interesting: 'yes'

# provide a bit of additional context
Raven.extra_context happiness: 'very'
```

Additionally, if you're using Rack (without the middleware), you can easily provide context with the ``rack_context`` helper:

```ruby
Raven.rack_context(env)
```

If you're using the Rack middleware, we've already taken care of cleanup for you, otherwise you'll need to ensure you perform it manually:

```ruby
Raven::Context.clear!
```

Note: the rack and user context will perform a set operation, whereas tags and extra context will merge with any existing request context.

### Authlogic

When using Authlogic for authentication, you can provide user context by binding to session ```after_persisting``` and ```after_destroy``` events in ```user_session.rb```:

```ruby
class UserSession < Authlogic::Session::Base
  # events binding
  after_persisting :raven_set_user_context
  after_destroy :raven_clear_user_context

  def raven_set_user_context
    Raven.user_context( { 'id' => self.user.id, 'email' => self.user.email, 'username' => self.user.username } )
  end

  def raven_clear_user_context
    Raven.user_context({})
  end
end
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

As of [v0.10.0](https://github.com/getsentry/raven-ruby/blob/21cb3164e0d0ab91394ba98b78195c4f6342b4bb/changelog.md#0100), events will be sent to Sentry in all environments. If you do not wish
to send events in an environment, we suggest you unset the ```SENTRY_DSN```
variable in that environment.

Alternately, you can configure Raven to run only in certain environments by configuring the `environments` whitelist. For example, to only run Sentry in production:

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

You can find the list of exceptions that are excluded by default in [Raven::Configuration::IGNORE_DEFAULT](https://github.com/getsentry/raven-ruby/blob/master/lib/raven/configuration.rb). Remember you'll be overriding those defaults by setting this configuration.

### Tags

You can configure default tags to be sent with every event. These can be
overridden in the context or event.

```ruby
Raven.configure do |config|
  config.tags = { environment: Rails.env }
end
```

### SSL Verification

By default SSL certificate verification is **disabled** in the client. This choice
was made due to root CAs not being commonly available on systems. If you'd like
to change this, you can enable verification by passing the ``ssl_verification``
flag:

```ruby
Raven.configure do |config|
  config.ssl_verification = true
end
```

### Asynchronous Delivery

When an error occurs, the notification is immediately sent to Sentry. Raven can be configured
to send notifications asynchronously:

```ruby
Raven.configure do |config|
  config.async = lambda { |event|
    Thread.new { Raven.send(event) }
  }
end
```

This example uses a thread, but other tools can be used (GirlFriday, Resque, Sidekiq, etc...) as
long as the `event` argument is eventually passed to `Raven.send`.

### Logging

You can use any logger with Raven - just set config.logger. Raven respects logger
levels.

```ruby
logger = ::Logger.new(STDOUT)
logger.level = ::Logger::WARN

Raven.configure do |config|
  config.logger = logger
end
```

If you are using Rails, Raven will default to using Rails.logger as the logger.

### Encoding

While unlikely that you'll need to change it, by default Raven compresses outgoing messages with gzip. This has a slight impact on performance, but due to the size of many Ruby stacktrace it's required for the serve to accept the content.

To disable gzip, set the encoding to 'json':

```ruby
Raven.configure do |config|
  config.encoding = 'json'
end
```

### Silencing the ready message

Upon start, Raven will write the following message to the log at the INFO level:

    ** [out :: hostname.example.com] I, [2014-07-22T15:32:57.498368 #30897]  INFO -- : ** [Raven] Raven 0.9.4 ready to catch errors"

You can turn off this message by passing `true` to `Raven.configure`

```ruby
Raven.configure(true) do |config|
   ...
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

## Testing Your Configuration

To ensure you've setup your configuration correctly we recommend running the
included rake task::

```bash
$ rake raven:test[https://public:secret@app.getsentry.com/3825]
Client configuration:
-> server: https://app.getsentry.com
-> project_id: 3825
-> public_key: public
-> secret_key: secret

Sending a test event:
-> event ID: 033c343c852b45c2a3add98e425ea4b4

Done!
```

A couple of things to note:

* This won't test your environment configuration. The test CLI forces your
  configuration to represent itself as if it were running in the production env.
* If you're running within Rails (or anywhere else that will bootstrap the
  rake environment), you should be able to omit the DSN argument.

## Contributing

### Bootstrap

```bash
$ bundle install
```

### Running the test suite

```bash
$ rake spec
```

Resources
---------

* [Bug Tracker](http://github.com/getsentry/raven-ruby/issues>)
* [Code](http://github.com/getsentry/raven-ruby>)
* [Mailing List](https://groups.google.com/group/getsentry>)
* [IRC](irc://irc.freenode.net/sentry>)  (irc.freenode.net, #sentry)
