0.11.0
------

- Raven now captures exceptions in Rake tasks automatically. [nateberkopec, troelskn #222]
- There is now a configuration option called ```should_send``` that can be configured to use a Proc to determine whether or not an event should be sent to Sentry. This can be used to implement rate limiters, etc. [nateberkopec, #221]
- Raven now includes three event processors by default instead of one, which can be turned on and off independently. [nateberkopec, #223]
- Fixed bug with YAJL compatibility. [nateberkopec, #223]

0.10.1
------

- Updated to RSpec 3.
- Apply filters to encoded JSON data.


0.10.0
------

- Events are now sent to Sentry in all environments. To change this behavior, either unset ```SENTRY_DSN``` or explicitly configure it via ```Raven.configure```.
- gzip is now the default encoding
- Removed hashie dependency


0.9.0
-----

- Native support for Delayed::Job [pkuczynski, #176]
- Updated to Sentry protocol version 5


0.5.0
-----
- Rails 2 support [sluukonen, #45]
- Controller methods in Rails [jfirebaugh]
- Runs by default in any environment other than test, cucumber, or development. [#81]
