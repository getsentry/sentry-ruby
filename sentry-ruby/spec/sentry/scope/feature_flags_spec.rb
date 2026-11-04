# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Scope do
  subject(:scope) { described_class.new }

  before do
    perform_basic_setup { |config| config.traces_sample_rate = 1.0 }
  end

  describe "#add_feature_flag" do
    it "adds flags to event contexts" do
      scope.add_feature_flag("a", true)
      scope.add_feature_flag(:b, false)

      event = scope.apply_to_event(Sentry::ErrorEvent.new(configuration: Sentry.configuration))
      expect(event.contexts[:flags]).to eq(values: [{ flag: "a", result: true }, { flag: "b", result: false }])
    end

    it "ignores non-boolean results" do
      scope.add_feature_flag("a", "yes")
      scope.add_feature_flag("b", nil)
      expect(scope.flags.values).to be_empty
    end

    it "moves a re-evaluated flag to the end with its new result" do
      scope.add_feature_flag("a", true)
      scope.add_feature_flag("b", true)
      scope.add_feature_flag("a", false)
      expect(scope.flags.values).to eq("b" => true, "a" => false)
    end

    it "evicts the oldest flag beyond the limit" do
      (Sentry::Scope::MAX_FLAGS + 1).times { |i| scope.add_feature_flag("f#{i}", true) }
      expect(scope.flags.values.size).to eq(Sentry::Scope::MAX_FLAGS)
      expect(scope.flags.values.first.first).to eq("f1")
    end

    it "does not add flags to transaction events" do
      scope.add_feature_flag("a", true)
      transaction = Sentry.start_transaction(name: "foo", op: "bar")
      event = scope.apply_to_event(Sentry::TransactionEvent.new(configuration: Sentry.configuration, transaction: transaction))
      expect(event.contexts).not_to have_key(:flags)
    end

    it "does not add flags to check-in events" do
      scope.add_feature_flag("a", true)
      event = Sentry::CheckInEvent.new(configuration: Sentry.configuration, slug: "foo", status: :ok)
      scope.apply_to_event(event)
      expect(event.contexts).not_to have_key(:flags)
    end

    it "is isolated in duplicated and updated scopes and cleared by #clear" do
      scope.add_feature_flag("a", true)
      copy = scope.dup
      copy.add_feature_flag("b", true)
      copy.add_feature_flag("a", false)
      expect(scope.flags.values).to eq("a" => true)

      updated = described_class.new
      updated.update_from_scope(scope)
      updated.add_feature_flag("b", true)
      expect(scope.flags.values).to eq("a" => true)

      scope.clear
      expect(scope.flags.values).to be_empty
    end

    context "with an active span" do
      let(:span) { Sentry::Span.new(transaction: nil) }
      before { scope.set_span(span) }

      it "records flag.evaluation.* span data, capped per span" do
        scope.add_feature_flag("a", true)
        expect(span.to_h[:data]["flag.evaluation.a"]).to eq(true)

        12.times { |i| scope.add_feature_flag("g#{i}", true) }
        keys = span.to_h[:data].keys.select { |k| k.start_with?("flag.evaluation.") }
        expect(keys.size).to eq(Sentry::Span::MAX_FLAGS)

        scope.add_feature_flag("a", false)
        expect(span.to_h[:data]["flag.evaluation.a"]).to eq(true)
      end
    end
  end

  describe "Sentry.add_feature_flag" do
    it "adds to the current scope" do
      Sentry.add_feature_flag("x", true)
      expect(Sentry.get_current_scope.flags.values).to eq("x" => true)
    end
  end
end
