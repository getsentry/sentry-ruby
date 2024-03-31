require "rails/generators/base"

class SentryGenerator < ::Rails::Generators::Base
  class_option :dsn, type: :string, desc: "Sentry DSN"

  def copy_initializer_file
    dsn = options[:dsn] ? "'#{options[:dsn]}'" : "ENV['SENTRY_DSN']"

    create_file "config/initializers/sentry.rb", <<~RUBY
      # frozen_string_literal: true

      Sentry.init do |config|
        config.breadcrumbs_logger = [:active_support_logger]
        config.dsn = #{dsn}
      end
    RUBY
  end
end
