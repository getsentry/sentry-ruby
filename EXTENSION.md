## What's an extension?

An extension is a gem built on top of the core Ruby SDK (`sentry-ruby`) that provides additional functionality or integration support to the users. For example, `sentry-rails` and `sentry-sidekiq` are SDK extensions that offer integration support with specific libraries. 

## Sentry::Integrable

You can write extensions for `sentry-ruby` any way you want to. But if you're going to build an extension for integration support, `sentry-ruby` provides a module called `Sentry::Integrable` that will save you some work.

### Usage

Let me use `sentry-rails` as our example.

#### Register the extension

```ruby
require "sentry-ruby"

# the integrable module needs to be required separately
require "sentry/integrable" 

module Sentry
  # the module/class of the extension should be defined under the Sentry namespace
  module Rails 
    
    # extend the module
    extend Integrable 
    
    # use the register_integration method to register your extension to the SDK core
    register_integration name: "rails", version: Sentry::Rails::VERSION
  end
end
```

Once the extension is registered, it will do 2 things for you:

1. It'll generate `.capture_exception` and `.capture_message` methods for your extension. In our example, they'll be `Sentry::Rails.capture_exception` and `Sentry::Rails.capture_message`.
2. It'll also generate the SDK meta for the extension, which is `{name: "sentry.ruby.rails", version: Sentry::Rails::VERSION}` in this case.

#### Use the generated helpers

All the integration-level exception/message should be captured via the newly generated helpers in the extension gem. This is because:

- Those helpers will inject `{ integration: "integration_name" }` to the event hints. So you or the users can later identify each event's source in the `before_send` callback.
- Events created from those helpers will have the integration meta as their SDK information.
- In the future, we might also introduce more advanced integration-based features. And those features will rely on these helpers.

### Future plan

- Methods like `configure_integration` for generating integration-level config options, like `config.integration_name.option_name`.
- Support integration-specific excluded exceptions list.

