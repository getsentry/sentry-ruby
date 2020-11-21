# frozen_string_literal: true
require "securerandom"

module Sentry
  class Span
    STATUS_MAP = {
      400 => "invalid_argument",
      401 => "unauthenticated",
      403 => "permission_denied",
      404 => "not_found",
      409 => "already_exists",
      429 => "resource_exhausted",
      499 => "cancelled",
      500 => "internal_error",
      501 => "unimplemented",
      503 => "unavailable",
      504 => "deadline_exceeded"
    }


    attr_reader :trace_id, :span_id, :parent_span_id, :sampled, :start_timestamp, :timestamp, :description, :op, :status, :tags, :data
    attr_accessor :span_recorder

    def initialize(description: nil, op: nil, status: nil, trace_id: nil, parent_span_id: nil, sampled: nil, start_timestamp: nil, timestamp: nil)
      @trace_id = trace_id || SecureRandom.uuid.delete("-")
      @span_id = SecureRandom.hex(8)
      @parent_span_id = parent_span_id
      @sampled = sampled
      @start_timestamp = start_timestamp || Time.now.utc.to_f
      @timestamp = timestamp
      @description = description
      @op = op
      @status = status
      @data = {}
      @tags = {}
      @span_recorder = SpanRecorder.new(1000)
      @span_recorder.add(self)
    end

    def finish
      # already finished
      return if @timestamp

      @timestamp = Time.now.utc.to_f
    end

    def to_sentry_trace
      sampled_flag = ""
      sampled_flag = @sampled ? 1 : 0 unless @sampled.nil?

      "#{@trace_id}-#{@span_id}-#{sampled_flag}"
    end

    def to_hash
      {
        trace_id: @trace_id,
        span_id: @span_id,
        parent_span_id: @parent_span_id,
        start_timestamp: @start_timestamp,
        timestamp: @timestamp,
        description: @description,
        op: @op,
        status: @status,
        tags: @tags,
        data: @data
      }
    end

    def get_trace_context
      {
        trace_id: @trace_id,
        span_id: @span_id,
        description: @description,
        op: @op,
        status: @status
      }
    end

    def start_child(**options)
      options = options.dup.merge(trace_id: @trace_id, parent_span_id: @span_id, sampled: @sampled)
      child_span = Span.new(options)
      child_span.span_recorder = @span_recorder
      @span_recorder.add(child_span)
      child_span
    end

    def set_op(op)
      @op = op
    end

    def set_description(description)
      @description = description
    end

    def set_status(status)
      @status = status
    end

    def set_timestamp(timestamp)
      @timestamp = timestamp
    end

    def set_http_status(status_code)
      status_code = status_code.to_i
      set_data("status_code", status_code)

      status =
        if status_code >= 200 && status_code < 299
          "ok"
        else
          STATUS_MAP[status_code]
        end
      set_status(status)
    end

    def set_data(key, value)
      @data[key] = value
    end

    def set_tag(key, value)
      @tags[key] = value
    end

    class SpanRecorder
      attr_reader :max_length, :spans

      def initialize(max_length)
        @max_length = max_length
        @spans = []
      end

      def add(span)
        if @spans.count < @max_length
          @spans << span
        end
      end
    end
  end
end
