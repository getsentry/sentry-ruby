Processors
==========

Raven Ruby contains several "processors", which scrub data before it is sent to Sentry.
Processors remove invalid or sensitive data. The following are the processors
which are enabled by default (and are applied to all outgoing data in this order):

RemoveCircularReferences
   Many Ruby JSON implementations simply throw an exception if they detect a
   circular reference. This processor removes circular references from hashes
   and arrays.

UTF8Conversion
   Many Ruby JSON implementations will throw exceptions if data is not in a
   consistent UTF-8 format. This processor looks for invalid encodings and fixes
   them.

SanitizeData
  Censors any data which looks like a password, social security number or credit
  card number. Can be configured to scrub other data.

Cookies
  Removes any HTTP cookies from the Sentry event data.

PostData
  Removes any HTTP Post request bodies.

HTTPHeaders
  Removes all HTTP headers which match a regex. By default, this will only remove the
  "Authorization" header, but can be configured to remove others.

Finally, another processor is included in the source but is not turned on by default,
RemoveStackTrace.

To remove stacktraces from events:

.. sourcecode:: ruby

    Raven.configure do |config|
      config.processors += [Raven::Processor::RemoveStacktrace]
    end

Writing Your Own Processor
--------------------------

Processors are simple to write and understand. As an example, let's say that we
send user API keys to a background job (using Sidekiq), and if the background job
raises an exception, we want to make sure that the API key is removed from the
event data.

This is what a basic processor might look like:

.. sourcecode:: ruby

  class MyJobProcessor < Raven::Processor
    def process(data)
      return data unless data["extra"]["arguments"] &&
        data["extra"]["arguments"].first["sensitive_parameter"]

      data["extra"]["arguments"].first["sensitive_parameter"] = STRING_MASK
      data
    end
  end

Processors should inherit from the ``Raven::Processor`` class. This ensures that the
processor has access to its client (all processors have a ``client`` instance method,
which will be populated with the current ``Raven::Client`` when the  processor
is initialized), and gives you a few convenient constants for masking data.

Processors must have a method called ``process`` defined. It must accept one
argument, which will be the Raven event data hash. The method must return a hash,
which represents the data after it has been modified by the processor.

To help you in writing your own processor, here is what the Event data hash looks
like (slightly modified/concatenated) when it is passed to the processor:

.. sourcecode:: ruby

  {
    "environment" => "default",
    "event_id" => "02ea6d3d35c840b1a8f339ba896917e3",
    "extra" => {
      "server" => {
       # server related information
      }
     "active_job" => "MyActiveJob",
     "arguments" => [ {"sensitive_parameter": "sensitive"} ],
     "job_id" => "cbc2c146-0486-4e98-b81c-1a251d636b34",
    },
    "modules" => {
      "rake"=>"12.0.0",
       "concurrent-ruby"=>"1.0.5",
       "i18n"=>"0.8.6",
       "minitest"=>"5.10.3",
       # ...
    },
    "platform" => "ruby",
    "release" => "e4d5ced",
    "sdk" => {"name"=>"raven-ruby", "version"=>"2.6.3"},
    "server_name" => "myserver.local",
    "timestamp" => "2017-10-09T19:53:20",
    "exception" => {
      # A very large and complex exception object
    }
  }

However, it will probably be more helpful if you use a debugger, such as `pry`, to
inspect the event data hash for yourself.

The example processor given above looks for the ActiveJob arguments hash, looks for
a particular value, and then replaces it with the string mask. There is a fast return
if the event does not contain the ActiveJob data we're looking for, using Ruby 2.3+'s
safe navigation operator.

Once you have your processor written, you simply need to add it to the processor chain:

.. sourcecode:: ruby

  Raven.configure do |config|
    config.processors += MyJobProcessor
  end

For more information about writing processors, read the code for the default
processors, located in ``lib/processor``.
