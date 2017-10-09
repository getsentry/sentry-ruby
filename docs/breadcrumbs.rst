.. versionadded:: 1.2

Breadcrumbs
===========

Breadcrumbs are a trail of events which happened prior to an issue. Often, these events are very similar to traditional logs, but Breadcrumbs also can record rich, structured data.

.. sourcecode:: ruby

    Raven.breadcrumbs.record do |crumb|
      crumb.data = data
      crumb.category = name
      # ...
    end

The following attributes are available:

* ``category``: A String to label the event under. This will usually be the same as a logger name, and will let you more easily understand the area an event took place, such as "auth".
* ``data``: A Hash of metadata around the event. This is often used instead of message, but may also be used in addition.
* ``level``: The level may be any of ``error``, ``warn``, ``info``, or ``debug``.
* ``message``: A string describing the event. The most common vector, often used as a drop-in for a traditional log message.
* ``timestamp``: A Unix timestamp (seconds past epoch)

Appropriate places to inject Breadcrumbs may be places like your HTTP library:

.. sourcecode:: ruby

    # Instrumenting Faraday with a middleware:

    class RavenFaradayMiddleware
      def call
        # Add a breadcrumb every time we complete an HTTP request
        @app.call(request_env).on_complete do |response_env|
          Raven.breadcrumbs.record do |crumb|
            crumb.data = { response_env: response_env }
            crumb.category = "faraday"
            crumb.timestamp = Time.now.to_i
            crumb.message = "Completed request to #{request_env[:url]}"
          end
        end
      end
    end

.. versionadded:: 2.6

The breadcrumb buffer is publicly accessible if you wish to manipulate it beyond
what is possible with the ``record`` method.

.. sourcecode:: ruby

  Raven.breadcrumbs.buffer # Array of breadcrumbs
