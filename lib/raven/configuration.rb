require 'logger'
require 'uri'
require 'ostruct'

module Raven
  class Configuration

    attr_accessor :data

    IGNORE_DEFAULT = ['ActiveRecord::RecordNotFound',
                      'ActionController::RoutingError',
                      'ActionController::InvalidAuthenticityToken',
                      'CGI::Session::CookieStore::TamperedWithCookie',
                      'ActionController::UnknownAction',
                      'AbstractController::ActionNotFound',
                      'Mongoid::Errors::DocumentNotFound']

    def initialize
      self.data = OpenStruct.new
      self.server = ENV['SENTRY_DSN'] if ENV['SENTRY_DSN']
      @context_lines = 3
      data.current_environment = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'default'
      data.send_modules = true
      data.excluded_exceptions = IGNORE_DEFAULT
      data.processors = [Raven::Processor::RemoveCircularReferences, Raven::Processor::UTF8Conversion, Raven::Processor::SanitizeData]
      data.ssl_verification = false
      data.encoding = 'gzip'
      data.timeout = 1
      data.open_timeout = 1
      data.tags = {}
      data.async = false
      data.catch_debugged_exceptions = true
      data.sanitize_fields = []
    end

    def server=(value)
      uri = URI.parse(value)
      uri_path = uri.path.split('/')

      if uri.user
        # DSN-style string
        data.project_id = uri_path.pop
        data.public_key = uri.user
        data.secret_key = uri.password
      end

      data.scheme = uri.scheme
      data.host = uri.host
      data.port = uri.port if uri.port
      data.path = uri_path.join('/')

      # For anyone who wants to read the base server string
      data.server = "#{data.scheme}://#{data.host}"
      data.server << ":#{data.port}" unless data.port == { 'http' => 80, 'https' => 443 }[data.scheme]
      data.server << data.path
    end
    alias_method :dsn=, :server=

    def encoding=(encoding)
      raise ArgumentError.new('Unsupported encoding') unless ['gzip', 'json'].include? encoding
      data.encoding = encoding
    end

    def async=(value)
      raise ArgumentError.new("async must be callable (or false to disable)") unless (value == false || value.respond_to?(:call))
      data.async = value
    end
    def async?; async; end

    # Allows config options to be read like a hash
    #
    # @param [Symbol] option Key for a given attribute
    def [](option)
      data.send(option)
    end

    def send_in_current_environment?
      !!server && (!environments || environments.include?(current_environment))
    end

    private

    def method_missing(method, args = nil)
      args ? data.public_send(method, args) : data.public_send(method)
    end
  end
end
