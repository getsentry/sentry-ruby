# frozen_string_literal: true

module Sentry
  class Configuration
    attr_reader :resque

    add_post_initialization_callback do
      @resque = Sentry::Resque::Configuration.new
    end
  end

  module Resque
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
