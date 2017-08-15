Puma
====

Installation
------------

Install the SDK via Rubygems by adding it to your ``Gemfile``:

.. sourcecode:: ruby

    gem "sentry-raven"

Configuration
-------------

Puma provides a config option for handling low level errors.

.. sourcecode:: ruby

    # in your puma.rb config
    lowlevel_error_handler do |ex, env|
      Raven.capture_exception(
        ex,
        :message => ex.message,
        :extra => { :puma => env },
        :transaction => "Puma"
      )
      # note the below is just a Rack response
      [500, {}, ["An error has occurred, and engineers have been informed. Please reload the page. If you continue to have problems, contact support@example.com\n"]]
    end
