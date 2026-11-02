<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <picture>
      <source srcset="https://sentry-brand.storage.googleapis.com/sentry-logo-white.png" media="(prefers-color-scheme: dark)" />
      <source srcset="https://sentry-brand.storage.googleapis.com/sentry-wordmark-dark-280x84.png" media="(prefers-color-scheme: light), (prefers-color-scheme: no-preference)" />
      <img src="https://sentry-brand.storage.googleapis.com/sentry-wordmark-dark-280x84.png" alt="Sentry" width="280">
    </picture>
  </a>
  <br>
</p>

# sentry-resque, the Resque integration for Sentry's Ruby client

---


[![Gem Version](https://img.shields.io/gem/v/sentry-resque.svg)](https://rubygems.org/gems/sentry-resque)
![Build Status](https://github.com/getsentry/sentry-ruby/actions/workflows/tests.yml/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-resque.svg)](https://rubygems.org/gems/sentry-resque/)
[![SemVer](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-resque&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-resque&package-manager=bundler&version-scheme=semver)


[Documentation](https://docs.sentry.io/platforms/ruby/guides/resque/) | [Bug Tracker](https://github.com/getsentry/sentry-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Getting Started

### Install

```ruby
gem "sentry-ruby"
gem "sentry-resque"
```

Then you're all set! `sentry-resque` will automatically insert a custom middleware and error handler to capture exceptions from your workers!
