# frozen_string_literal: true

module Sentry
  class Attachment
    PathNotFoundError = Class.new(StandardError)

    attr_reader :bytes, :filename, :path, :add_to_transactions

    def initialize(bytes: nil, filename: nil, path: nil, add_to_transactions: false)
      @bytes = bytes
      @filename = infer_filename(filename, path)
      @path = path
      @add_to_transactions = add_to_transactions
    end

    def to_envelope_headers
      { type: 'attachment', filename: filename }
    end

    def payload
      @payload ||= if bytes
        bytes
      else
        File.binread(path)
      end
    rescue Errno::ENOENT
      raise PathNotFoundError, "Failed to read attachment file, file not found: #{path}"
    end

    private

    def infer_filename(filename, path)
      return filename if filename

      if path
        File.basename(path)
      else
        raise ArgumentError, "filename or path is required"
      end
    end
  end
end
