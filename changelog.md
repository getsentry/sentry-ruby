0.10.1
------

- Updated to RSpec 3.
- Apply filters to encoded JSON data.


0.10.0
------

- Breaking: by default, no environments will be ignored. Previously "test", "cucumber" and "development" environments were ignored by default.
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
