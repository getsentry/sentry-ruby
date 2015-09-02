Configuration
=============

Configuration is passed as part of the client initialization:

.. code-block:: javascript

    Raven.configure do |config|
      config.dsn = '___DSN___'
      config.attr = 'value'
    end

Optional settings
-----------------

.. describe:: logger

    The name of the logger used by Sentry. Default: ``''``

    .. code-block:: ruby

        config.logger = 'default'

.. describe:: release

    Track the version of your application in Sentry.

    .. code-block:: ruby

        config.release = '721e41770371db95eee98ca2707686226b993eda'

Environment Variables
---------------------

.. describe:: SENTRY_DSN

    Optionally declare the DSN to use for the client through the environment. Initializing the client in your app won't require setting the DSN.
