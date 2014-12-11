require 'zlib'
require 'base64'

require 'raven/version'
require 'raven/okjson'
require 'raven/transports/http'
require 'raven/transports/udp'

module Raven

  class Client

    PROTOCOL_VERSION = '5'
    USER_AGENT = "raven-ruby/#{Raven::VERSION}"
    CONTENT_TYPE = 'application/json'

    attr_accessor :configuration

    def initialize(configuration)
      @configuration = configuration
      @processors = configuration.processors.map { |v| v.new(self) }
      @state = ClientState.new
    end

    def send(event)
      unless configuration.send_in_current_environment?
        configuration.log_excluded_environment_message
        return
      end

      # Set the project ID correctly
      event.project = self.configuration.project_id

      if !@state.should_try?
        Raven.logger.error "Not sending event #{event.id} due to previous failure"
        return
      end

      Raven.logger.debug "Sending event #{event.id} to Sentry"

      content_type, encoded_data = encode(event)
      begin
        transport.send(generate_auth_header, encoded_data,
                       :content_type => content_type)
      rescue => e
        failed_send(e)
        return
      end

      successful_send()

      event
    end

    private

    def encode(event)
      hash = event.to_hash

      # apply processors
      hash = @processors.reduce(hash) do |memo, processor|
        processor.process(memo)
      end

      encoded = OkJson.encode(hash)

      case self.configuration.encoding
      when 'gzip'
        gzipped = Zlib::Deflate.deflate(encoded)
        b64_encoded = strict_encode64(gzipped)
        return 'application/octet-stream', b64_encoded
      else
        return 'application/json', encoded
      end
    end

    def transport
      @transport ||=
        case self.configuration.scheme
        when 'udp'
          Transports::UDP.new self.configuration
        when 'http', 'https'
          Transports::HTTP.new self.configuration
        else
          raise Error.new("Unknown transport scheme '#{self.configuration.scheme}'")
        end
    end

    def generate_auth_header
      now = Time.now.to_i.to_s
      fields = {
        'sentry_version' => PROTOCOL_VERSION,
        'sentry_client' => USER_AGENT,
        'sentry_timestamp' => now,
        'sentry_key' => self.configuration.public_key,
        'sentry_secret' => self.configuration.secret_key,
      }
      'Sentry ' + fields.map { |key, value| "#{key}=#{value}" }.join(', ')
    end

    private

    def strict_encode64(string)
      if Base64.respond_to? :strict_encode64
        Base64.strict_encode64 string
      else # Ruby 1.8
        Base64.encode64(string)[0..-2]
      end
    end

    def successful_send
      @state.success()
    end

    def failed_send(e)
      @state.failure()
      Raven.logger.error "Unable to record event with remote Sentry server (#{e.class} - #{e.message})"
      e.backtrace[0..10].each { |line| Raven.logger.error(line) }
    end

  end

  class ClientState
    def initialize
      reset
    end

    def should_try?
      return true if @status == :online

      interval = @retry_after || [@retry_number, 6].min ** 2
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
