# Raven-Ruby

[![Gem Version](https://img.shields.io/gem/v/sentry-raven.svg)](https://rubygems.org/gems/sentry-raven)
[![Build Status](https://img.shields.io/travis/getsentry/raven-ruby/master.svg)](https://travis-ci.org/getsentry/raven-ruby)

A client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.

## Requirements

We test on Ruby 1.9, 2.2 and 2.3 at the latest patchlevel/teeny version. Our Rails integration works with Rails 4.2+. JRuby support is experimental - check TravisCI to see if the build is passing or failing.

## Getting Started

### Install

```ruby
gem "sentry-raven"
```

### Raven only runs when SENTRY_DSN is set

Raven will capture and send exceptions to the Sentry server whenever its DSN is set. This makes environment-based configuration easy - if you don't want to send errors in a certain environment, just don't set the DSN in that environment!

```bash
# Set your SENTRY_DSN environment variable.
export SENTRY_DSN=http://public:secret@example.com/project-id
```
```ruby
# Or you can configure the client in the code (not recommended - keep your DSN secret!)
Raven.configure do |config|
  config.dsn = 'http://public:secret@example.com/project-id'
end
```

### Raven doesn't report some kinds of data by default.

Raven ignores some exceptions by default - most of these are related to 404s or controller actions not being found. [For a complete list, see the `IGNORE_DEFAULT` constant](https://github.com/getsentry/raven-ruby/blob/master/lib/raven/configuration.rb).

Raven doesn't report POST data or cookies by default. In addition, it will attempt to remove any obviously sensitive data, such as credit card or Social Security numbers. For more information about how Sentry processes your data, [check out the documentation on the `processors` config setting.](https://docs.getsentry.com/hosted/clients/ruby/config/)

### Call

If you use Rails, you're already done - no more configuration required! Check [Integrations](https://docs.getsentry.com/hosted/clients/ruby/integrations/) for more details on other gems Sentry integrates with automatically.

Otherwise, Raven supports two methods of capturing exceptions:

```ruby
Raven.capture do
  # capture any exceptions which happen during execution of this block
  1 / 0
end

begin
  1 / 0
rescue ZeroDivisionError => exception
  Raven.capture_exception(exception)
end
```

## More Information

* [Documentation](https://docs.getsentry.com/hosted/clients/ruby/)
* [Bug Tracker](https://github.com/getsentry/raven-ruby/issues>)
* [Code](https://github.com/getsentry/raven-ruby>)
* [Mailing List](https://groups.google.com/group/getsentry>)
* [IRC](irc://irc.freenode.net/sentry>)  (irc.freenode.net, #sentry)
