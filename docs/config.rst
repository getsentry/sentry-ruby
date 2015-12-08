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

.. describe:: async

    When an error occurs, the notification is immediately sent to Sentry. Raven can be configured to send notifications asynchronously:

    .. code-block:: ruby

        config.async = lambda { |event|
            Thread.new { Raven.send_event(event) }
        }

.. describe:: encoding

    While unlikely that you'll need to change it, by default Raven compresses outgoing messages with gzip. This has a slight impact on performance, but due to the size of many Ruby stacktrace it's required for the serve to accept the content.

    To disable gzip, set the encoding to 'json':

    .. code-block:: ruby

        config.encoding = 'json'

.. describe:: excluded_exceptions

    If you never wish to be notified of certain exceptions, specify 'excluded_exceptions' in your config file.

    In the example below, the exceptions Rails uses to generate 404 responses will be suppressed.

    .. code-block:: ruby

        config.excluded_exceptions = ['ActionController::RoutingError', 'ActiveRecord::RecordNotFound']

    You can find the list of exceptions that are excluded by default in ``Raven::Configuration::IGNORE_DEFAULT``. Remember you'll be overriding those defaults by setting this configuration.

.. describe:: logger

    The name of the logger used by Sentry. Default: ``''``

    .. code-block:: ruby

        config.logger = 'default'

.. describe:: release

    Track the version of your application in Sentry.

    .. code-block:: ruby

        config.release = '721e41770371db95eee98ca2707686226b993eda'

.. describe:: tags

    Default tags to send with each event.

    .. code-block:: ruby

        config.tags = { environment: Rails.env }


Environment Variables
---------------------

.. describe:: SENTRY_DSN

    Optionally declare the DSN to use for the client through the environment. Initializing the client in your app won't require setting the DSN.
