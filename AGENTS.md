# Agent Instructions

## Package Manager
Use **Bundler**. Each gem has its own `Gemfile`; run commands from within the gem subdirectory.
```bash
cd sentry-ruby && bundle install
```

## Monorepo Structure
| Gem | Path | Description |
|-----|------|-------------|
| `sentry-ruby` | `sentry-ruby/` | Core SDK — all other gems depend on this |
| `sentry-rails` | `sentry-rails/` | Rails integration |
| `sentry-sidekiq` | `sentry-sidekiq/` | Sidekiq integration |
| `sentry-resque` | `sentry-resque/` | Resque integration |
| `sentry-delayed_job` | `sentry-delayed_job/` | DelayedJob integration |
| `sentry-opentelemetry` | `sentry-opentelemetry/` | OpenTelemetry integration |

Shared test infrastructure lives in `lib/sentry/test/`. Root `Gemfile.dev` defines shared dev dependencies.

## File-Scoped Commands
Run from within the target gem directory (e.g. `cd sentry-ruby`):

| Task | Command |
|------|---------|
| Install deps | `bundle install` |
| Run all tests | `bundle exec rake` |
| Run single spec | `bundle exec rspec spec/sentry/client_spec.rb` |
| Lint | `bundle exec rubocop path/to/file.rb` |
| Lint (autofix) | `bundle exec rubocop -a path/to/file.rb` |

Root-level `bundle exec rubocop` lints the entire repo. Root-level `bundle exec rake` runs the E2E/integration spec suite (not individual gem tests).

## Testing Conventions
- Framework: **RSpec**
- Spec files mirror source: `lib/sentry/client.rb` → `spec/sentry/client_spec.rb`
- Isolated specs go in `spec/isolated/` (loaded in separate processes)
- `sentry-rails` has `spec/versioned/` for Ruby-version-specific specs
- Environment variables control version matrices: `RAILS_VERSION`, `SIDEKIQ_VERSION`, `RACK_VERSION`, `REDIS_RB_VERSION`
- Every behavioral change needs a spec. Bug fixes need a regression test.

## Commit Attribution
AI commits MUST include:
```
Co-Authored-By: <agent-name> <noreply@example.com>
```

## Standards Overrides
- Changelog: DO NOT update `CHANGELOG.md` as it is automatically generated during the release process
- Linting: RuboCop with `rubocop-rails-omakase` base — see `.rubocop.yml`
- See `CONTRIBUTING.md` for release process and contribution workflow
