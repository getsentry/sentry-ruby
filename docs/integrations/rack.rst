Rack (Sinatra etc.)
===================

Add ``use Raven::Rack`` to your ``config.ru`` or other rackup file (this is
automatically inserted in Rails):

.. sourcecode:: ruby

    require 'raven'

    Raven.configure(true) do |config|
      config.dsn = '___DSN___'
    end

    use Raven::Rack
