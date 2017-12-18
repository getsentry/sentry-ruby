module Raven
  module Utils
    class Release
      attr_accessor :logger

      def initialize(logger)
        self.logger = logger
      end

      def detect_release
        detect_release_from_git ||
          detect_release_from_capistrano ||
          detect_release_from_heroku
      rescue StandardError => ex
        logger.error "Error detecting release: #{ex.message}"
      end

      private

      def detect_release_from_git
        release = `git rev-parse --short HEAD 2>/dev/null`.strip if File.directory?('.git')
        return nil if release == ''
        release
      rescue StandardError
        nil
      end

      def detect_release_from_capistrano
        revision_file = File.join(project_root, 'REVISION')
        revision_log = File.join(project_root, '..', 'revisions.log')

        if File.exist?(revision_file)
          File.read(revision_file).strip
        elsif File.exist?(revision_log)
          File.open(revision_log).to_a.last.strip.sub(/.*as release ([0-9]+).*/, '\1')
        end
      end

      def detect_release_from_heroku
        return unless running_on_heroku?
        logger.warn(heroku_dyno_metadata_message) && return unless ENV['HEROKU_SLUG_COMMIT']

        ENV['HEROKU_SLUG_COMMIT']
      end

      def running_on_heroku?
        File.directory?("/etc/heroku")
      end

      def heroku_dyno_metadata_message
        "You are running on Heroku but haven't enabled Dyno Metadata. For Sentry's "\
        "release detection to work correctly, please run `heroku labs:enable runtime-dyno-metadata`"
      end
    end
  end
end
