# frozen_string_literal: true

require "spec_helper"

# isolated tests need a SimpleCov name otherwise they will overwrite coverage
SimpleCov.command_name "RSpecVersioned_2.7_ActiveJob"

RSpec.describe "ActiveJob integration", type: :job do
  before do
    make_basic_app
  end

  let(:event) do
    transport.events.last.to_json_compatible
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "returns #perform method's return value" do
    expect(NormalJob.perform_now).to eq("foo")
  end

  describe "ActiveJob arguments serialization" do
    it "serializes range begin-less and end-less arguments gracefully when Range consists of ActiveSupport::TimeWithZone" do
      post = Post.create!

      range_no_beginning = (..1.day.ago)
      range_no_end = (5.days.ago..)

      expect do
        JobWithArgument.perform_now("foo", { bar: Sentry },
          integer: 1, post: post, range_no_beginning: range_no_beginning, range_no_end: range_no_end)
      end.to raise_error(RuntimeError)

      event = transport.events.last.to_json_compatible
      expect(event.dig("extra", "arguments")).to eq(
        [
          "foo",
          { "bar" => "Sentry" },
          {
            "integer" => 1,
            "post" => post.to_global_id.to_s,
            "range_no_beginning" => "..#{range_no_beginning.last}",
            "range_no_end" => "#{range_no_end.first}.."
          }
        ]
      )
    end
  end
end
