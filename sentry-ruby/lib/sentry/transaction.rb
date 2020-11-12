module Sentry
  class Transaction < Span
    UNLABELD_NAME = "<unlabeled transaction>".freeze

    attr_reader :name, :parent_sampled

    def initialize(name: nil, parent_sampled: nil, **options)
      super(**options)

      @name = name
      @parent_sampled = parent_sampled
    end

    def to_hash
      hash = super
      hash.merge!(name: @name, sampled: @sampled, parent_sampled: @parent_sampled)
      hash
    end

    def finish(hub: nil)
      super() # Span#finish doesn't take arguments

      if @name.nil?
        @name = UNLABELD_NAME
      end

      return unless @sampled

      hub ||= Sentry.get_current_hub
      event = hub.current_client.event_from_transaction(self)
      hub.capture_event(event)
    end
  end
end
