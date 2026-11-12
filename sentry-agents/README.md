# sentry-agents, RubyLLM tracing for Sentry's Ruby client

[![Build Status](https://github.com/getsentry/sentry-ruby/actions/workflows/tests.yml/badge.svg)](https://github.com/getsentry/sentry-ruby/actions/workflows/tests.yml)

`sentry-agents` integrates [RubyLLM](https://github.com/crmne/ruby_llm) with Sentry. Loading the gem instruments the global RubyLLM configuration when Sentry is initialized.

For an isolated RubyLLM context, install the adapter explicitly:

```ruby
context = RubyLLM.context
Sentry::Agents::RubyLLM.install(context)
```

## Requirements

- Ruby >= 3.1.3
- RubyLLM 2.x

## Installation

Add the gem to your bundle:

```ruby
gem "sentry-agents"
```

## Workflows

`RubyLLM.workflow` and its steps create pipeline grouping spans. Chat and tool descendants carry `gen_ai.pipeline.name` without being labeled as agent runs.

## GenAI data collection

Configure prompt and completion content independently:

```ruby
Sentry.init do |config|
  config.data_collection.gen_ai.inputs = true
  config.data_collection.gen_ai.outputs = false
end
```

These settings only control GenAI content. HTTP body, breadcrumb, and exception-local collection have separate controls; disabling GenAI content is not a blanket redaction switch.
