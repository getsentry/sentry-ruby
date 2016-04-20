Usage
=====

To use Raven Ruby all you need is your DSN.  Like most Sentry libraries it
will honor the ``SENTRY_DSN`` environment variable.  You can find it on
the project settings page under API Keys.  You can either export it as
environment variable or manually configure it with ``Raven.configure``:

.. code-block:: ruby

    Raven.configure do |config|
      config.dsn = '___DSN___'
    end

If you only want to send events to Sentry in certain environments, you
should set ``config.environments`` too:

.. code-block:: ruby

    Raven.configure do |config|
      config.dsn = '___DSN___'
      config.environments = ['staging', 'production']
    end

Reporting Failures
------------------

If you use Rails, Rake, Rack etc, you're already done - no more
configuration required! Check :doc:`integrations/index` for more details on
other gems Sentry integrates with automatically.

Otherwise, Raven supports two methods of capturing exceptions:

.. sourcecode:: ruby

    Raven.capture do
      # capture any exceptions which happen during execution of this block
      1 / 0
    end

    begin
      1 / 0
    rescue ZeroDivisionError => exception
      Raven.capture_exception(exception)
    end

Reporting Messages
------------------

If you want to report a message rather than an exception you can use the
``capture_message`` method:

.. code-block:: ruby

    Raven.capture_message("Something went very wrong")

Referencing Events
------------------

The client exposes a ``last_event_id`` accessor allowing you to easily
reference the last captured event. This is useful, for example, if you wanted
to show the user a reference on your error page::

.. code-block:: ruby

    # somewhere deep in the stack
    Raven.capture do
      1 / 0
    end

Now you can easily expose this to your error handler:

.. code-block:: ruby

    class ErrorsController < ApplicationController
      def internal_server_error
        render(:status => 500, :sentry_event_id => Raven.last_event_id)
      end
    end

Optional Attributes
-------------------

With calls to ``capture_exception`` or ``capture_message`` additional data
can be supplied::

  .. code-block:: ruby

      Raven.capture_message("...", :attr => 'value')

.. describe:: extra

    Additional context for this event. Must be a mapping. Children can be any native JSON type.

    .. code-block:: ruby

        {
            :extra => {'key' => 'value'}
        }

.. describe:: fingerprint

    The fingerprint for grouping this event.

    .. code-block:: ruby

        {
            :fingerprint => ['{{ default }}', 'other value']
        }

.. describe:: level

    The level of the event. Defaults to ``error``.

    .. code-block:: ruby

        {
            :level => 'warning'
        }

    Sentry is aware of the following levels:

    * debug (the least serious)
    * info
    * warning
    * error
    * fatal (the most serious)

.. describe:: logger

    The logger name for the event.

    .. code-block:: ruby

        {
            :logger => 'default'
        }

.. describe:: tags

    Tags to index with this event. Must be a mapping of strings.

    .. code-block:: ruby

        {
            :tags => {'key' => 'value'}
        }

.. describe:: user

    The acting user.

    .. code-block:: ruby

        {
            :user => {
                'id' => 42,
                'email' => 'clever-girl'
            }
        }
