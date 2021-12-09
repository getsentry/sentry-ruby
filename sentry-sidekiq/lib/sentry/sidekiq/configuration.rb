module Sentry
  class Configuration
    attr_reader :sidekiq

    add_post_initialization_callback do
      @sidekiq = Sentry::Sidekiq::Configuration.new
    end
  end

  module Sidekiq
    class Configuration
      # Set this option to true if you want Sentry to only capture the last job
      # retry if it fails.
      attr_accessor :report_after_job_retries

      def initialize
        @report_after_job_retries = false
      end
    end
  end
end
