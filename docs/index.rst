.. sentry:edition:: self

    Raven Ruby
    ==========

.. sentry:edition:: hosted, on-premise

    .. class:: platform-ruby

    Ruby
    ====

Raven for Ruby is a client and integration layer for the Sentry error
reporting API.  It supports Ruby MRI 1.8.7/REE, 1.9.3, 2.0, 2.1 and 2.2.
JRuby support is provided but experimental.

Installation
------------

Raven Ruby comes as a gem and is straightforward to install.  If you are
using Bundler just add this to your ``Gemfile``:

.. sourcecode:: ruby

    gem "sentry-raven"

For other means of installation see :ref:`install`.

Configuration
-------------

To use Raven Ruby all you need is your DSN.  Like most Sentry libraries it
will honor the ``SENTRY_DSN`` environment variable.  You can find it on
the project settings page under API Keys.  You can either export it as
environment variable or manually configure it with ``Raven.configure``:

.. sourcecode:: ruby

    Raven.configure do |config|
      config.dsn = '___DSN___'
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

Additional Context
------------------

Much of the usefulness of Sentry comes from additional context data with
the events.  Raven Ruby makes this very convenient by providing
methods to set thread local context data that is then submitted
automatically with all events.

There are three primary methods for providing request context:

.. sourcecode:: ruby

    # bind the logged in user
    Raven.user_context email: 'foo@example.com'

    # tag the request with something interesting
    Raven.tags_context interesting: 'yes'

    # provide a bit of additional context
    Raven.extra_context happiness: 'very'

For more information see :doc:`context`.

Deep Dive
---------

Want to know more?  We have a detailed documentation about all parts of
the library and the client integrations.


.. toctree::
   :maxdepth: 2
   :titlesonly:

   install
   usage
   context
   integrations/index

Resources:

* `Bug Tracker <http://github.com/getsentry/raven-ruby/issues>`_
* `Github Project <http://github.com/getsentry/raven-ruby>`_
