<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br />
</p>

# Contributing

We welcome suggested improvements and bug fixes in the form of pull requests. The guide below will help you get started, but if you have further questions, please feel free to reach out on [Discord](https://discord.gg/Ww9hbqr).


## Making a release

Install and use `craft`: https://github.com/getsentry/craft

Make sure the `CHANGELOG.md` is update and latest `master` contains all changes.

Run:

```bash
craft prepare x.x.x
```

Where `x.x.x` stands for the version you want to release.
Afterwards reach out to an employee of Sentry, they will cut a release by running the `publish` process of `craft`.
