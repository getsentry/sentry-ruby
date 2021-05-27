<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br>
</p>

# sentry-lambda, the AWS Lambda integration for Sentry's Ruby client

---



The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Requirements

Ruby version >= 2.5

## Getting Started

### Install

```ruby
gem "sentry-lambda"
```

### Usage
```ruby
def lambda_handler(event:, context:)
  Sentry::Lambda.wrap_handler(event: event, context: context) do
    # Function logic here....
  end
end
```
#### Timeout Warnings
It can be important to know when a function is about to time out and to have sentry-level
details when this occurs. In order to give a Lambda Function time to do so, a warning message can
be enabled with `capture_timeout_warning: true` like so:
```ruby
def lambda_handler(event:, context:)
  Sentry::Lambda.wrap_handler(event: event, context: context, capture_timeout_warning: true) do
    # Function logic here....
  end
end
```

### Integration Specific Configuration

This gem has a few Lambda-specific configuration options.

Using an AWS CloudWatch LogGroup Trigger. This approach requires having a separate Lambda Function
which is triggered by this log. Simply outputting the `Sentry::Event` data as a log allows for the
event to be captured synchronously elsewhere and also gives the current Lambda more time to finish.
```ruby
Sentry.init do |config|
  # Put a log which will be caught by Trigger `?"SENTRY Event" ?"Task timed out after"`
  config.async = lambda do |event, hint|
    puts "SENTRY Event: #{event.to_json} Hint: #{hint.to_json}"
  end
end
```

Sending to Sentry Synchronously:
```ruby
Sentry.init { |config| config.background_worker_threads = 0 } # all events will be sent synchronously
```
