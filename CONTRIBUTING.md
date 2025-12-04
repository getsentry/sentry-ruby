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

## Develop This Project With Multi-root Workspaces

If you use editors that support [VS Code-style multi-root workspaces](https://code.visualstudio.com/docs/editor/multi-root-workspaces),
such as VS Code, Cursor...etc., opening the editor with `sentry-ruby.code-workspace` file will provide a better development experience.

## Working in a devcontainer

If you use [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension, you can open the project with the devcontainer by running `Remote-Containers: Reopen in Container` command.

The devcontainer is configured with `.devcontainer/.env` file, that you need to create:

```bash
cp .devcontainer/.env.example .devcontainer/.env
```

This file defines which specific image and Ruby version will be used to run the code. Edit it whenever you need to use a different image or Ruby version.

## Contribute To Individual Gems

- Install the dependencies of a specific gem by running `bundle` in it's subdirectory. I.e:
  ```bash
  cd sentry-sidekiq
  bundle install
  ```
- Install any additional dependencies. `sentry-sidekiq` assumes you have `redis` running.
- Use `bundle exec rake` to run tests.
  - In `sentry-rails`, you can use `RAILS_VERSION=version` to specify the Rails version to test against. Default is `8.0`
  - In `sentry-sidekiq`, you can use `SIDEKIQ_VERSION=version` to specify what version of Sidekiq to install when you run `bundle install`. Default is `7.0`
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


[bug report]: https://github.com/getsentry/sentry-ruby/issues/new?template=bug_report.md
[propose a feature]: https://github.com/getsentry/sentry-ruby/issues/new?template=feature_request.md
[extension guideline]: https://github.com/getsentry/sentry-ruby/blob/master/EXTENSION.md
[Sentry SDK spec]: https://develop.sentry.dev/sdk/unified-api/
[sentry-doc repo]: https://github.com/getsentry/sentry-docs
[Discord]: https://discord.gg/sentry
