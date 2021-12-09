<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br />
</p>

# General Guidance

You can contribute to this project in the following ways:

- Try out the master branch and provide feedback
- File a [bug report] or [propose a feature]
- Open a PR for bug fixes or implement requested features
- Give feedback to opened issues/pull requests
- Contribute documentation in the [sentry-doc repo]

And if you have any questions, please feel free to reach out on [Discord].

## Contribute To Individual Gems

- Use `bundle exec rake` to run tests.
  - In `sentry-rails`, you can use `RAILS_VERSION=version` to specify the Rails version to test against. Default is `6.1`
- Use example apps under the `example` or `examples` folder to test the change. (Remember to change the DSN first)
- To learn more about `sentry-ruby`'s structure, you can read the [Sentry SDK spec]

## Write Your Sentry Extension

Please read the [extension guideline] to learn more. Feel free to open an issue if you find anything missing.

# Release SDK Gem

## Before the Release

1. Run the example app(s) of the gem and make sure all the events are reported successfully.
2. Update the changelog's latest `Unreleased` title with the target version.

### Minor-version releases

- Make sure all the new features are documented properly in the changelog. This includes but not limited to:
  - Explanation of the feature.
  - Sample code for the feature.
  - Expected changes on the SDK's behavior and/or on the reported events.
  - Some related screenshots.
- Prepare a PR in the [sentry-doc repo] to update relevant content depending on the changes in the new release.

### Major-version releases

In addition to all the steps listed above, you also need to:

- Write a migration guide to
  - Outline the major changes done in this release.
  - Explain why upgrading is beneficial.
  - List all the breaking changes and help users make related changes in their apps.
- Update gem READMEs.
- May need to check related wizard files in the [sentry-doc repo].

## Prepare the Release

1. Visit the [`Prepare Release`](https://github.com/getsentry/sentry-ruby/actions/workflows/prepare_release.yml) workflow.
2. Click `Run workflow`.
3. Fill in the required fields and run the workflow.

### Extra Steps

4. Once `sentry-ruby` is released, you need to bump the required version of `sentry-ruby-core` in the integration gems before releasing them.


[bug report]: https://github.com/getsentry/sentry-ruby/issues/new?template=bug_report.md
[propose a feature]: https://github.com/getsentry/sentry-ruby/issues/new?template=feature_request.md
[extension guideline]: https://github.com/getsentry/sentry-ruby/blob/master/EXTENSION.md
[Sentry SDK spec]: https://develop.sentry.dev/sdk/unified-api/
[sentry-doc repo]: https://github.com/getsentry/sentry-docs
[Discord]: https://discord.gg/Ww9hbqr
