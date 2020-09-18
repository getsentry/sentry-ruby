module Sentry
  class Client
    class State
      def initialize
        reset
      end

      def should_try?
        return true if @status == :online

        interval = @retry_after || [@retry_number, 6].min**2
        return true if Time.now - @last_check >= interval

        false
      end

      def failure(retry_after = nil)
        @status = :error
        @retry_number += 1
        @last_check = Time.now
        @retry_after = retry_after
      end

      def success
        reset
      end

      def reset
        @status = :online
        @retry_number = 0
        @last_check = nil
        @retry_after = nil
      end

      def failed?
        @status == :error
      end
    end
  end
end
