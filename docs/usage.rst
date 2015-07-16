Usage
=====

To use Raven Ruby all you need is your DSN.  Like most Sentry libraries it
will honor the ``SENTRY_DSN`` environment variable.  You can find it on
the project settings page under API Keys.  You can either export it as
environment variable or manually configure it with ``Raven.configure``:

.. sourcecode:: ruby

    Raven.configure do |config|
      config.dsn = '___DSN___'
    end

If you only want to send events to Sentry in certain environments, you
should set ``config.environments`` too:

.. sourcecode:: ruby

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

.. sourcecode:: ruby

    Raven.capture_message("Something went very wrong")

Additional Data
---------------

With calls to ``capture_exception`` or ``capture_message`` additional data
can be supplied.  You can either do it at the time the call is made or you
can use the context helpers (see :doc:`context`).

To provide a user for instance, you can invoke a method like this:

.. sourcecode:: ruby

    Raven.capture_message("Something went very wrong", :user => {
        'id' => 42,
        'email' => 'clever-girl'
    })
