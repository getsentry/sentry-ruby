<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br>
</p>

# sentry-rails, the Rails integration for Sentry's Ruby client

---


[![Gem Version](https://img.shields.io/gem/v/sentry-rails.svg)](https://rubygems.org/gems/sentry-rails)
![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-rails%20Test/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-rails.svg)](https://rubygems.org/gems/sentry-rails/)
[![SemVer](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-rails&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-rails&package-manager=bundler&version-scheme=semver)


[Documentation](https://docs.sentry.io/clients/ruby/) | [Bug Tracker](https://github.com/getsentry/sentry-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Requirements

This integration requires Rails version >= 5.0 and Ruby version >= 2.4

## Getting Started

### Install

```ruby
gem "sentry-rails"
```

### Integration Specific Configuration

This gem has a few Rails-specific configuration options

```ruby
Sentry.init do |config|
  # report exceptions rescued by ActionDispatch::ShowExceptions or ActionDispatch::DebugExceptions middlewares
  # the default value is true
  config.rails.report_rescued_exceptions = true

  # this gem also provides a new breadcrumb logger that accepts instrumentaions from ActiveSupport
  # it's not activated by default, but you can enable it with
  config.breadcrumbs_logger = [:active_support_logger]
end
```

