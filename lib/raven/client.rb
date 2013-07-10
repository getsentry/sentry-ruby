require 'zlib'
require 'base64'

require 'raven/version'
require 'raven/okjson'
require 'raven/transports/http'
require 'raven/transports/udp'

module Raven

  class Client

    PROTOCOL_VERSION = '3'
    USER_AGENT = "raven-ruby/#{Raven::VERSION}"
    CONTENT_TYPE = 'application/json'

    attr_accessor :configuration

    def initialize(configuration)
      @configuration = configuration
      @processors = configuration.processors.map { |v| v.new(self) }
    end

    def send(event)
      if !configuration.send_in_current_environment?
        Raven.logger.debug "Event not sent due to excluded environment: #{configuration.current_environment}"
        return
      end

      # Set the project ID correctly
      event.project = self.configuration.project_id
      Raven.logger.debug "Sending event #{event.id} to Sentry"

      content_type, encoded_data = encode(event)
      begin
        transport.send(generate_auth_header(encoded_data), encoded_data,
                     :content_type => content_type)
      rescue => e
        Raven.logger.error "Unable to record event with remote Sentry server (#{e.class} - #{e.message})"
        return
      end

      return event
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
        b64_encoded = Base64.strict_encode64(gzipped)
        return 'application/octet-stream', b64_encoded
      else
        return 'application/json', encoded
      end
    end

    def transport
      @transport ||= case self.configuration.scheme
        when 'udp'
          Transports::UDP.new self.configuration
        when 'http', 'https'
          Transports::HTTP.new self.configuration
        else
          raise Error.new("Unknown transport scheme '#{self.configuration.scheme}'")
        end
    end

    def generate_auth_header(data)
      now = Time.now.to_i.to_s
      fields = {
        'sentry_version' => PROTOCOL_VERSION,
        'sentry_client' => USER_AGENT,
        'sentry_timestamp' => now,
        'sentry_key' => self.configuration.public_key,
        'sentry_secret' => self.configuration.secret_key,
      }
      'Sentry ' + fields.map{|key, value| "#{key}=#{value}"}.join(', ')
    end

  end

end
