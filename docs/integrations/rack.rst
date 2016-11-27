Rack (Sinatra etc.)
===================

Installation
------------

Install the SDK via Rubygems by adding it to your ``Gemfile``:

.. sourcecode:: ruby

    gem "sentry-raven"

Configuration
-------------

Add ``use Raven::Rack`` to your ``config.ru`` or other rackup file (this is
automatically inserted in Rails):

.. sourcecode:: ruby

    require 'raven'

    Raven.configure do |config|
      config.dsn = '___DSN___'
    end

    use Raven::Rack
