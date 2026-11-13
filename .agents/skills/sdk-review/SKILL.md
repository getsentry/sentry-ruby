---
name: sdk-review
description: "Review sentry-ruby changes for violations of Sentry SDK contracts: host-app safety, data-collection gates, supported versions, public API, and Ruby-specific rules."
allowed-tools: Read Grep Glob
---
Review only the changed code. Report a finding only if you can point to the exact line and show how it breaks a user's app, build or data. Most hunks break no SDK contract, so no findings is the normal result. Generic logic bugs belong to `code-review`; this skill only covers SDK contracts.

## Core SDK rules (same in every SDK repo)

1. **Never break the host app** (high). SDK code that can raise, block, or change the user's behavior: exceptions, return values, signatures, job or request flow.
2. **Data collected without its gate** (high). Request or response bodies, headers, cookies, user info, `gen_ai` inputs/outputs or DB results that the SDK collects automatically and sends without the matching data-collection option or its filtering. The [data collection spec](https://develop.sentry.dev/sdk/foundations/client/data-collection/) defines the options; data the user sets explicitly is never gated.
3. **Supported versions** (high). Language, runtime, target or dependency APIs newer than the repo's declared minimum, used without a guard. MRI minimums come from `required_ruby_version` and the dependency constraints in each `sentry-*/sentry-*.gemspec`. JRuby is also supported, but its versions come from the CI matrix (`sentry-*/test-matrix.json`, `.mise.ci.toml`), not the gemspec, and its extra dependencies sit in `platform :jruby` blocks in the Gemfiles. MRI-only APIs or gems used without a JRuby guard are a finding.
4. **Public API** (medium). Breaking public changes without a deprecation path, or internals exposed as public API.

## Do not report (same in every SDK repo)

- Style, naming, refactors, or anything the repo's linters, type checkers or analyzers catch.
- Pre-existing code the diff does not change.
- Behavior that an issue, the PR description or official Sentry documentation specifies, or a trade-off the PR or its threads explain. Other SDKs are a reference, not proof of the expected behavior.
- Follow-ups the PR says are handled in a stacked PR or the major branch.
- Tests, samples and examples, unless they can't fail or they teach wrong SDK usage.
- Edge cases that need misuse or very unlikely timing.

## Ruby rules

5. **Job integrations** (high). Sidekiq, Resque, DelayedJob or ActiveJob hooks that can skip enqueue or perform, or corrupt the payload, when SDK code fails.
6. **Scope or hub leaks** (medium). Per-job or per-request scope not pushed and popped on every path (failure, retry, shutdown), or a cloned hub left behind.
7. **Errors lost or reported twice** (medium). For example ActiveJob plus the native integration both reporting, or errors before perform being dropped.
8. **Optional gems** (high). A `nil` config, or a gem that isn't loaded or autoloaded, crashing at boot.

Also do not report truthiness bugs that assume `0` or `""` are falsy (they are truthy in Ruby), or "unguarded" calls without checking the callers first.
