# frozen_string_literal: true

require "sentry/data_collection/key_value_collection"

module Sentry
  class DataCollection
    # Configuration for the categories of data collected by the SDK.
    # Replacement for send_default_pii.
    # Spec: https://develop.sentry.dev/sdk/foundations/client/data-collection/
    #
    # @example Configure data collection
    #   Sentry.init do |config|
    #     data_collection = config.data_collection
    #     data_collection.user_info = true
    #     data_collection.cookies.mode = :deny_list
    #     data_collection.cookies.terms = ["session", "token"]
    #     data_collection.http_headers.request.mode = :deny_list
    #     data_collection.http_headers.request.terms = nil
    #     data_collection.http_headers.response.mode = :allow_list
    #     data_collection.http_headers.response.terms = ["my_special_header"]
    #     data_collection.http_bodies = [:incoming_request]
    #     data_collection.url_query_params.mode = :allow_list
    #     data_collection.url_query_params.terms = ["page", "limit"]
    #     data_collection.graphql.document = true
    #     data_collection.graphql.variables = true
    #     data_collection.database_query_data = true
    #     data_collection.queues = true
    #     data_collection.stack_frame_variables = true
    #     data_collection.frame_context_lines = 5
    #   end

    MODES = %i[off deny_list allow_list].freeze

    PII_HEADER_SNIPPETS = %w[forwarded -ip _ip remote via _user -user].freeze

    BODY_TYPES = %i[
      incoming_request
      outgoing_request
      incoming_response
      outgoing_response
    ].freeze

    class HttpHeaders
      # @return [KeyValueCollection]
      attr_accessor :request

      # @return [KeyValueCollection]
      attr_accessor :response

      def initialize(request:, response:)
        @request = request
        @response = response
      end
    end

    class GraphQL
      # @return [Boolean]
      attr_accessor :document

      # @return [Boolean]
      attr_accessor :variables

      def initialize(document:, variables:)
        @document = document
        @variables = variables
      end
    end

    # @return [Boolean]
    # @default `true`
    attr_accessor :user_info

    # @return [KeyValueCollection]
    # @default `mode: :deny_list, terms: nil`
    attr_accessor :cookies

    # @return [HttpHeaders]
    # @default request and response use `mode: :deny_list, terms: nil`
    attr_accessor :http_headers

    # @return [Array<Symbol>] containing values from BODY_TYPES
    # @default `nil` (all valid body types)
    attr_accessor :http_bodies

    # @return [KeyValueCollection]
    # @default `mode: :deny_list, terms: nil`
    attr_accessor :url_query_params

    # @return [Boolean]
    # @default `true`
    attr_accessor :database_query_data

    # @return [GraphQL]
    # @default `document: true, variables: true`
    attr_accessor :graphql

    # @return [Boolean]
    # @default `true`
    attr_accessor :queues

    # @return [Boolean]
    # @default `false`
    attr_accessor :stack_frame_variables

    # @return [Integer]
    # @default `3`
    attr_accessor :frame_context_lines

    # Filters key-value data using the default sensitive denylist.
    def self.filter(values)
      default_filter.filter(values)
    end

    def self.default_filter
      @default_filter ||= KeyValueCollection.new(mode: :deny_list, terms: nil)
    end

    # Builds data collection settings compatible with the legacy send_default_pii
    # configuration.
    def self.backfill(configuration)
      # the new DataCollection defaults are already correct if pii is enabled
      data_collection = new
      return data_collection if configuration.send_default_pii

      # TODO-neel-data map to exact ruby behaviour for backwards compat behavior
      data_collection.user_info = false
      data_collection.cookies.mode = :off
      data_collection.http_headers.request.mode = :deny_list
      data_collection.http_headers.request.terms = PII_HEADER_SNIPPETS
      data_collection.http_headers.response.mode = :deny_list
      data_collection.http_headers.response.terms = PII_HEADER_SNIPPETS
      data_collection.http_bodies = []
      data_collection.url_query_params.mode = :off
      data_collection.graphql.document = false
      data_collection.graphql.variables = false
      data_collection.database_query_data = false
      data_collection.queues = false
      data_collection.stack_frame_variables = configuration.include_local_variables
      data_collection.frame_context_lines = configuration.context_lines
      data_collection
    end

    def initialize
      @user_info = true
      @cookies = KeyValueCollection.new(mode: :deny_list, terms: nil)
      @http_headers = HttpHeaders.new(
        request: KeyValueCollection.new(mode: :deny_list, terms: nil),
        response: KeyValueCollection.new(mode: :deny_list, terms: nil)
      )
      @http_bodies = BODY_TYPES.dup
      @url_query_params = KeyValueCollection.new(mode: :deny_list, terms: nil)
      @database_query_data = true
      @graphql = GraphQL.new(document: true, variables: true)
      @queues = true
      @stack_frame_variables = false
      @frame_context_lines = 3
    end

    # Returns whether incoming HTTP request bodies should be collected.
    # nil implies all BODY_TYPES according to spec
    def collect_incoming_http_body?
      http_bodies.nil? || http_bodies.include?(:incoming_request)
    end

    # Returns whether outgoing HTTP request bodies should be collected.
    # nil implies all BODY_TYPES according to spec
    def collect_outgoing_http_body?
      http_bodies.nil? || http_bodies.include?(:outgoing_request)
    end
  end
end
