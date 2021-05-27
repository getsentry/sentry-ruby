# Changelog

## 0.1.1
## Bug Fixes
[sentry-lambda.gemspec]
```ruby
spec.files = Dir['lib/**/*.rb']
```

## 0.1.0

First version

## Bug Fixes
* Sentry::Event .timestamp should include milliseconds

## Features

* Adds Sentry::Lambda::CaptureExceptions

Creates a Rack-like integration which can be used in a lambda
function like so:

```ruby
def lambda_handler(event:, context:)
  Sentry::Lambda.wrap_handler(event: event, context: context) do
    # my biz logic here....
  end
end
```

A warning message can be enabled with `capture_timeout_warning: true` like so:
```ruby
def lambda_handler(event:, context:)
  Sentry::Lambda.wrap_handler(event: event, context: context, capture_timeout_warning: true) do
    # my biz logic here....
  end
end
```