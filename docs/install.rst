Installation
============

Raven Ruby comes as a gem and is straightforward to install.  If you are
using Bundler just add this to your ``Gemfile``:

.. sourcecode:: ruby

    gem "sentry-raven"

Development Version
-------------------

If you want to install the development version from github:

.. sourcecode:: ruby

    gem "sentry-raven", :github => "getsentry/raven-ruby"

Without Integrations
--------------------

If you wish to activate integrations manually (or don't want them
activated by default), require "raven/base" instead of "raven" or
"sentry-raven".  In that case disable the requiring in the ``Gemfile``:

.. sourcecode:: ruby

    gem "sentry-raven", :require => false

And in your initialization code:

.. sourcecode:: ruby

    require "raven/base"
    require "raven/integrations/rails"
    require "raven/integrations/delayed_job"

This stops you from calling ``Raven.inject``, which is where all this
integration loading occurs.
