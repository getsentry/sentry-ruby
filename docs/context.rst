Context
=======

Additional context can be passed to the capture methods.  This allows you
to record extra information that could help you identify the root cause of
the issue or who the error happened for.

.. sourcecode:: ruby

    Raven.capture_message 'My Event!',
      logger: 'logger',
      extra: {
        my_custom_variable: 'value'
      },
      tags: {
        foo: 'bar'
      }

The following attributes are available:

* ``logger``: the logger name to record this event under
* ``level``: a string representing the level of this event (fatal, error,
  warning, info, debug)
* ``server_name``: the hostname of the server
* ``tags``: a mapping of tags describing this event
* ``extra``: a mapping of arbitrary context
* ``user``: a mapping of user context
* ``transaction``: An array of strings. The final element in the array represents the current transaction, e.g. "HelloController#hello_world" for a Rails controller.

Providing Request Context
-------------------------

Most of the time you're not actually calling out to Raven directly, but
you still want to provide some additional context. This lifecycle
generally constists of something like the following:

*   Set some context via a middleware (e.g. the logged in user)
*   Send all given context with any events during the request lifecycle
*   Cleanup context

There are three primary methods for providing request context.

User Context
~~~~~~~~~~~~

User context describes the current actor.

.. sourcecode:: ruby

    # bind the logged in user
    Raven.user_context(
      # a unique ID which represents this user
      id: current_user.id, # 1

      # the actor's email address, if available
      email: current_user.email, # "example@example.org"

      # the actor's username, if available
      username: current_user.username, # "foo"

      # the actor's IP address, if available
      ip_address: request.ip # '127.0.0.1'
    )

When dealing with anonymous users you will still want to send basic user context to ensure Sentry can count them against the unique users:

.. sourcecode:: ruby

    Raven.user_context(
      # the actor's IP address, if available
      ip_address: request.ip # '127.0.0.1'
    )

Tags
~~~~

You can provide a set of key/value pairs called tags which Sentry will index and aggregate. This will help you understand the distribution of issues, as well as enabling easy lookup via search.

.. sourcecode:: ruby

    # tag the request with something interesting
    Raven.tags_context(
      language: I18n.locale, # "en-us"
      timezone: current_user.time_zone # "PST"
    )


Additional Context
~~~~~~~~~~~~~~~~~~

In addition to the supported structured data of Sentry, you can provide additional context. This is a key/value mapping, where the values must be JSON compatible, but can be of a rich datatype.

.. sourcecode:: ruby

    # provide a bit of additional context
    Raven.extra_context(
      happiness: 'very',
      emoji: ['much']
    )

Rack (HTTP) Context
~~~~~~~~~~~~~~~~~~~

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

Transactions
~~~~~~~~~~~~

The "transaction" is intended to represent the action the event occurred during.
In Rack, this will be the request URL. In Rails, it's the controller name and
action ("HelloController#hello_world").

Transactions are modeled as a stack. The top item in the stack (i.e. the last
element of the array) will be used as the ``transaction`` for any events:

.. sourcecode:: ruby

    Raven.context.transaction.push "User Import"
    # import some users
    Raven.context.transaction.pop

Transactions may also be overridden/set explicitly during event creation:

.. sourcecode:: ruby

    Raven.capture_exception(exception, transaction: "User Import")
