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
