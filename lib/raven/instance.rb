module Raven
  # A copy of Raven's base module class methods, minus some of the integration
  # and global hooks since it's meant to be used explicitly. Useful for
  # sending errors to multiple sentry projects in a large application.
  #
  # @example
  #   class Foo
  #     def initialize
  #       @other_raven = Raven::Instance.new
  #       @other_raven.configure do |config|
  #         config.server = 'http://...'
  #       end
  #     end
  #
  #     def foo
  #       # ...
  #     rescue => e
  #       @other_raven.capture_exception(e)
  #     end
  #   end
  class Instance
    attr_writer :client
    attr_accessor :configuration, :breadcrumbs

    def initialize(context = nil, config = nil)
      @context = @explicit_context = context
      self.configuration = config || Configuration.new
      # TODO: allow instances to have their own breadcrumb buffers
      # self.breadcrumbs = breadcrumbs || BreadcrumbBuffer.current
    end

    def breadcrumbs
      BreadcrumbBuffer.current
    end

    def context
      if @explicit_context
        @context ||= Context.new
      else
        Context.current
      end
    end

    def logger
      configuration.logger
    end

    # The client object is responsible for delivering formatted data to the
    # Sentry server.
    def client
      @client ||= Client.new(configuration)
    end

    # Tell the log that the client is good to go
    def report_status
      return if configuration.silence_ready
      if configuration.capture_allowed?
        logger.info "Raven #{VERSION} ready to catch errors"
      else
        logger.info "Raven #{VERSION} configured not to capture errors: #{configuration.error_messages}"
      end
    end

    # Call this method to modify defaults in your initializers.
    #
    # @example
    #   Raven.configure do |config|
    #     config.server = 'http://...'
    #   end
    def configure
      yield(configuration) if block_given?
      report_status
      self
    end

    # Send an event to the configured Sentry server
    #
    # @example
    #   evt = Raven::Event.new(:message => "An error")
    #   Raven.send_event(evt)
    def send_event(event)
      client.send_event(event)
    end

    # Capture and process any exceptions from the given block.
    #
    # @example
    #   Raven.capture do
    #     MyApp.run
    #   end
    def capture(options = {})
      if block_given?
        begin
          yield
        rescue Exception => e
          capture_type(e, options)
          raise
        end
      else
        install_at_exit_hook(options)
      end
    end

    def capture_type(obj, options = {})
      unless configuration.capture_allowed?(obj)
        logger.debug("#{obj} excluded from capture: #{configuration.error_messages}")
        return false
      end

      message_or_exc = obj.is_a?(String) ? "message" : "exception"
      options[:configuration] = configuration
      options[:context] = context
      if (evt = Event.send("from_" + message_or_exc, obj, options))
        yield evt if block_given?
        if configuration.async?
          begin
            # We have to convert to a JSON-like hash, because background job
            # processors (esp ActiveJob) may not like weird types in the event hash
            configuration.async.call(evt.to_json_compatible)
          rescue => ex
            logger.error("async event sending failed: #{ex.message}")
            send_event(evt)
          end
        else
          send_event(evt)
        end
        Thread.current["sentry_#{object_id}_last_event_id"] = evt.event_id
        evt
      end
    end

    alias capture_message capture_type
    alias capture_exception capture_type

    def last_event_id
      Thread.current["sentry_#{object_id}_last_event_id"]
    end

    # Bind user context. Merges with existing context (if any).
    #
    # It is recommending that you send at least the ``id`` and ``email``
    # values. All other values are arbitrary.
    #
    # @example
    #   Raven.user_context('id' => 1, 'email' => 'foo@example.com')
    def user_context(options = nil)
      context.user.merge!(options || {})
    end

    # Bind tags context. Merges with existing context (if any).
    #
    # Tags are key / value pairs which generally represent things like
    # application version, environment, role, and server names.
    #
    # @example
    #   Raven.tags_context('my_custom_tag' => 'tag_value')
    def tags_context(options = nil)
      context.tags.merge!(options || {})
    end

    # Bind extra context. Merges with existing context (if any).
    #
    # Extra context shows up as Additional Data within Sentry, and is
    # completely arbitrary.
    #
    # @example
    #   Raven.extra_context('my_custom_data' => 'value')
    def extra_context(options = nil)
      context.extra.merge!(options || {})
    end

    # TODO: does this need to be accessible?
    def rack_context(options = nil)
      context.rack_env.merge!(options || {})
    end

    private

    def install_at_exit_hook(options)
      at_exit do
        exception = $ERROR_INFO
        if exception
          logger.debug "Caught a post-mortem exception: #{exception.inspect}"
          capture_type(exception, options)
        end
      end
    end
  end
end
