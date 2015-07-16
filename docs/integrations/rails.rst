Ruby on Rails
=============

In Rails, all uncaught exceptions will be automatically reported.

You'll still want to ensure you've disabled anything that would prevent
errors from being propagated to the ``Raven::Rack`` middleware, ``like
ActionDispatch::ShowExceptions``:

.. sourcecode:: ruby

    config.action_dispatch.show_exceptions = false # this is the default setting in production

If you have added items to `Rails' log filtering
<http://guides.rubyonrails.org/action_controller_overview.html#parameters-filtering>`_,
you can also make sure that those items are not sent to Sentry:

.. sourcecode:: ruby

    # in your application.rb:
    config.filter_parameters << :password

    # in an initializer, like sentry.rb
    Raven.configure do |config|
      config.sanitize_fields = Rails.application.config.filter_parameters.map(&:to_s)
    end

If you only want to send events to Sentry in certain environments, you
should set ``config.environments`` too:

.. sourcecode:: ruby

    Raven.configure do |config|
      config.dsn = '___DSN___'
      config.environments = ['staging', 'production']
    end

Authlogic
---------

When using Authlogic for authentication, you can provide user context by
binding to session ``after_persisting`` and ``after_destroy`` events in
``user_session.rb``:

.. sourcecode:: ruby

    class UserSession < Authlogic::Session::Base
      # events binding
      after_persisting :raven_set_user_context
      after_destroy :raven_clear_user_context

      def raven_set_user_context
        Raven.user_context({
          'id' => self.user.id,
          'email' => self.user.email,
          'username' => self.user.username
        })
      end

      def raven_clear_user_context
        Raven.user_context({})
      end
    end
