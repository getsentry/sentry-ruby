<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br />
</p>

# Contributing

You can contribute this project in the following ways:

- File a [bug report] or propose a feature
- Open a PR for bug fixes or implementing requested features
- Give feedback to opened issues/pull requests
- Test the latest version - `gem 'sentry-raven', github: 'getsentry/raven-ruby'`
- Contribute documentation in the [document repo]


And if you have any questions, please feel free to reach out on [Discord].


[bug report]: https://github.com/getsentry/raven-ruby/issues/new?template=bug_report.md
[document repo]: https://github.com/getsentry/sentry-docs
[Discord]: https://discord.gg/Ww9hbqr

## How To Contribute

### Running Tests

#### RAILS_VERSION

Because this SDK supports multiple versions of Rails, or even without Rails, you might want to run your test against different versions of Rails.

You can do this by changing the `RAILS_VERSION` environment variable:


```
$ echo RAILS_VERSION=6.0
$ bundle update # this is necessary if you're switching between Rails versions
$ bundle exec rake
```

If not specified, it runs tests against `Rails 5.2`. 

And if you don't want to run the Rails related test cases, you can use `RAILS_VERSION=0`

```
$ RAILS_VERSION=0 bundle exec rake # runs without Rails related test cases
```

### Testing Your Change Against Example Rails Apps

We have a few example apps for different Rails versions under the `/examples` folder. You can use them to perform an end-to-end testing on your changes (just remember to change the DSN to your project's).

At this moment, we recommend testing against the [Rails 6 example](https://github.com/getsentry/raven-ruby/tree/master/examples/rails-6.0) first. Please read its readme to see what kind of testing you can perform with it.


## Making a release

Install and use `craft`: https://github.com/getsentry/craft

Make sure the `CHANGELOG.md` is update and latest `master` contains all changes.

Run:

```bash
craft prepare x.x.x
```

Where `x.x.x` stands for the version you want to release.
Afterwards reach out to an employee of Sentry, they will cut a release by running the `publish` process of `craft`.
