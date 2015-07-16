Context
=======

Additional context can be passed to the capture methods.  This allows you
to record extra information that could help you identify the root cause of
the issue or who the error happened for.

.. sourcecode:: ruby

    Raven.capture_message "My event",
      logger: 'logger',
      extra: {
        my_custom_variable: 'value'
      },
      tags: {
        environment: 'production'
      }

The following attributes are available:

* ``logger``: the logger name to record this event under
* ``level``: a string representing the level of this event (fatal, error,
  warning, info, debug)
* ``server_name``: the hostname of the server
* ``tags``: a mapping of tags describing this event
* ``extra``: a mapping of arbitrary context

Providing Request Context
-------------------------

Most of the time you're not actually calling out to Raven directly, but
you still want to provide some additional context. This lifecycle
generally constists of something like the following:

*   Set some context via a middleware (e.g. the logged in user)
*   Send all given context with any events during the request lifecycle
*   Cleanup context

There are three primary methods for providing request context:

.. sourcecode:: ruby

    # bind the logged in user
    Raven.user_context email: 'foo@example.com'

    # tag the request with something interesting
    Raven.tags_context interesting: 'yes'

    # provide a bit of additional context
    Raven.extra_context happiness: 'very'

Rack Context
------------

Additionally, if you're using Rack (without the middleware), you can
easily provide context with the ``rack_context`` helper:

.. sourcecode:: ruby

    Raven.rack_context(env)

If you're using the Rack middleware, we've already taken care of cleanup
for you, otherwise you'll need to ensure you perform it manually:

.. sourcecode:: ruby

    Raven::Context.clear!

Note: the rack and user context will perform a set operation, whereas tags
and extra context will merge with any existing request context.
