require 'faraday/middleware'

module Raven
  class Faraday
    # Faraday Middleware. Records a Raven breadcrumb every time
    # an HTTP request is completed by Faraday.
    class Breadcrumb < Faraday::Middleware
      def call(request_env)
        @app.call(request_env).on_complete do |response_env|
          Raven.breadcrumbs.record do |crumb|
            crumb.data = { response_env: response_env }
            crumb.category = "faraday"
            crumb.timestamp = Time.now.to_i
            crumb.message = "Completed request to #{request_env[:url]}"
          end
        end
      end
    end
  end
end
