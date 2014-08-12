0.10.0
------

- Environments are ignored by default unless explicitly set. To disable
  events it is recommend to unset the SENTRY_DSN value.


0.9.0
-----

- Native support for Delayed::Job [pkuczynski, #176]
- Updated to Sentry protocol version 5


0.5.0
-----
- Rails 2 support [sluukonen, #45]
- Controller methods in Rails [jfirebaugh]
- Runs by default in any environment other than test, cucumber, or development. [#81]
