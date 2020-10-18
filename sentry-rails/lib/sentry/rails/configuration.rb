module Sentry
  class Configuration
    attr_reader :rails

    def post_initialization_callback
      @rails = Sentry::Rails::Configuration.new
    end
  end

  module Rails
    class Configuration

    end
  end
end
