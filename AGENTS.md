# Agent Instructions

## Toolchain (mise)
[mise](https://mise.jdx.dev) manages Rubies and runs tasks. `.mise.toml` pins a single default Ruby for local work; `.mise.ci.toml` (loaded with `MISE_ENV=ci`) pins the full per-matrix Ruby set that CI, `bin/test`, and `bin/relock` resolve against.

```bash
mise install              # install the default toolchain (.mise.toml)
mise --env ci install     # install the full CI matrix of Rubies (needed for bin/test)
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
| `sentry-yabeda` | `sentry-yabeda/` | Yabeda integration |

Shared test infrastructure lives in `lib/sentry/test/`. Root `Gemfile.dev` defines shared dev dependencies.

## Testing
Use `bin/test` (from the repo root) to run a gem's specs under a single CI test-matrix cell — the local mirror of one CI job. The Ruby must already be installed (`mise --env ci install`).
You can also invoke `bin/test` from any of the gem directories themselves which automatically fills in the `--gem` part.

| Task | Command |
|------|---------|
| List every cell to choose from | `bin/test -l` |
| Run a gem (auto-picks newest installed Ruby cell) | `bin/test --gem sentry-rails` |
| Run a single spec | `bin/test --gem sentry-ruby spec/sentry/client_spec.rb` |
| Run a specific cell | `bin/test --cell sentry-ruby/gemfiles/ruby-3.3_rack-3_redis-4.gemfile` |
| Forward args to rspec | `bin/test --cell <cell> -- --tag foo` |
| Run full CI rake task | `bin/test --gem <gem> --rake` |

Root-level `bundle exec rake` runs the E2E/integration spec suite (not individual gem tests).

## Lint
Linting runs through mise tasks from the repo root. Rubocop lives in its own
`Gemfile.rubocop` (not the test matrix), which the tasks select automatically.

| Task | Command |
|------|---------|
| Lint the whole repo | `mise run lint` |
| Lint + autocorrect | `mise run lint:fix` |
| Lint specific paths | `mise run lint path/to/file.rb` |

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
